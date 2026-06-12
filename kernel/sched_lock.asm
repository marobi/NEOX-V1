; ============================================================
; sched_lock.asm
; NEOX - scheduler preemption guard helpers
;
; Purpose:
;   Provides the small non-sleeping guard used to prevent timer-
;   IRQ driven preemption while the kernel is inside scheduler-
;   critical state.
;
; Model:
;   - sched_lock bit 0 is the real guard bit.
;   - sched_lock_try_enter uses W65C02 TSB to test-and-set bit 0.
;   - C clear on return means this caller acquired the guard.
;   - C set on return means the guard was already held; the caller
;     must not enter scheduler-critical code and must not call leave.
;   - sched_lock_leave uses W65C02 TRB to clear bit 0.
;   - This is deliberately not a FIFO/sleepable gate. The scheduler
;     cannot block on itself and IRQ handlers cannot sleep/yield.
;   - This lock is not recursive.
;   - sched_lock_depth is diagnostic only: 0 = unlocked, 1 = locked.
;
; IRQ semantics:
;   - On successful try_enter, IRQ remains masked until leave or a
;     final BIOS handoff. This is the scheduler no-preemption window.
;   - On busy try_enter, the caller's previous P is restored and C=1
;     is returned.
;   - leave preserves the caller's A and P, including the caller's I
;     flag state.
; ============================================================

.setcpu "65C02"

.include "debug.inc"

.export sched_lock_try_enter
.export sched_lock_leave

.import active_pid
.import sched_debug_marker
.import sched_lock
.import sched_lock_owner
.import sched_lock_phase
.import sched_lock_depth
.import sched_lock_underflow

SCHED_LOCK_BIT = $01

.segment "KERN_TEXT"

; ------------------------------------------------------------
; sched_lock_try_enter
;
; Try to enter a scheduler-critical section.
;
; Return:
;   C clear = acquired; IRQ is masked and remains masked.
;   C set   = busy; caller did not acquire and must not leave.
;
; Clobbers: A, P
; Preserves: X, Y
; ------------------------------------------------------------

.proc sched_lock_try_enter
    php
    sei

    lda #SCHED_LOCK_BIT
    tsb sched_lock
    bne @busy

    ; The lock is now owned by this caller.  Discard the saved P
    ; instead of PLP: restoring P here would re-enable IRQs inside
    ; the scheduler critical section.
    pla

    ; DEBUG-BEGIN: temporary scheduler lock owner/enter diagnostic
    lda active_pid
    sta sched_lock_owner

    lda #DBG_SCHED_LOCK_ENTER
    sta sched_lock_phase

    lda #$01
    sta sched_lock_depth
    ; DEBUG-END: temporary scheduler lock owner/enter diagnostic

    clc
    rts

@busy:
    ; The bit was already set before TSB.  Keep IRQ masked while the
    ; busy diagnostic is recorded, then restore the caller's P because
    ; this caller did not acquire the scheduler guard.
    ; DEBUG-BEGIN: temporary scheduler lock busy diagnostic
    lda #DBG_MARK_SCHED_LOCK_OVERFLOW
    sta sched_debug_marker

    lda #DBG_SCHED_LOCK_NESTED
    sta sched_lock_phase
    ; DEBUG-END: temporary scheduler lock busy diagnostic

    plp
    sec
    rts
.endproc

; ------------------------------------------------------------
; sched_lock_leave
;
; Leave a scheduler-critical section.
;
; Contract:
;   Only callers that received C clear from sched_lock_try_enter may
;   call this routine.
;
; Preserves: A, X, Y, P
; ------------------------------------------------------------

.proc sched_lock_leave
    php
    pha
    sei

    lda sched_lock
    and #SCHED_LOCK_BIT
    beq @underflow

    lda #SCHED_LOCK_BIT
    trb sched_lock

    ; DEBUG-BEGIN: temporary scheduler lock outer-release diagnostic
    lda #DBG_OWNER_NONE
    sta sched_lock_owner

    stz sched_lock_phase
    stz sched_lock_depth
    ; DEBUG-END: temporary scheduler lock outer-release diagnostic
    bra @done

@underflow:
    ; DEBUG-BEGIN: temporary scheduler lock underflow diagnostic
    lda #DBG_MARK_SCHED_LOCK_UNDERFLOW
    sta sched_debug_marker

    lda #DBG_SCHED_LOCK_BAD_LEAVE
    sta sched_lock_phase

    stz sched_lock_depth

    lda sched_lock_underflow
    cmp #$ff
    beq @done
    inc sched_lock_underflow
    ; DEBUG-END: temporary scheduler lock underflow diagnostic

@done:
    pla
    plp
    rts
.endproc
