; ============================================================
; sched_lock.asm
; NEOX - scheduler preemption guard helpers
;
; Purpose:
;   Provides the small helper routines used to prevent timer-IRQ
;   driven preemption while the kernel is inside a scheduler-
;   critical section.
;
; Model:
;   - sched_lock is the real preemption guard counter.
;   - sched_lock_depth mirrors the intended nesting depth for
;     monitor/debug validation.
;   - sched_lock_owner is diagnostic only.  It is not enforced
;     because a scheduler handoff may enter the guard in one
;     process/context and leave it after selecting another.
;   - underflow/overflow are recorded, not trapped, so the RP
;     monitor remains usable.
;
; Usage rule:
;   Every sched_lock_enter must be balanced by a corresponding
;   sched_lock_leave on all exit paths.
; ============================================================

.setcpu "65C02"

.include "debug.inc"

.export sched_lock_enter
.export sched_lock_leave

.import current_pid
.import sched_debug_marker
.import sched_lock
.import sched_lock_owner
.import sched_lock_phase
.import sched_lock_depth
.import sched_lock_underflow

.segment "KERN_TEXT"

; ------------------------------------------------------------
; sched_lock_enter
;
; Enter a scheduler-critical section.
;
; Preserves: A, X, Y, P
; ------------------------------------------------------------

.proc sched_lock_enter
    php
    pha
    phx
    phy

    lda sched_lock
    beq @outermost

    cmp #$ff
    beq @overflow

    inc sched_lock
    inc sched_lock_depth

    ; DEBUG-BEGIN: temporary scheduler lock nested-entry diagnostic
    lda #DBG_SCHED_LOCK_NESTED
    sta sched_lock_phase
    ; DEBUG-END: temporary scheduler lock nested-entry diagnostic
    bra @done

@outermost:
    inc sched_lock

    ; DEBUG-BEGIN: temporary scheduler lock owner/enter diagnostic
    lda current_pid
    sta sched_lock_owner

    lda #DBG_SCHED_LOCK_ENTER
    sta sched_lock_phase

    lda #$01
    sta sched_lock_depth
    ; DEBUG-END: temporary scheduler lock owner/enter diagnostic
    bra @done

@overflow:
    ; DEBUG-BEGIN: temporary scheduler lock overflow diagnostic
    lda #DBG_MARK_SCHED_LOCK_OVERFLOW
    sta sched_debug_marker

    lda #DBG_SCHED_LOCK_NESTED
    sta sched_lock_phase
    ; DEBUG-END: temporary scheduler lock overflow diagnostic

@done:
    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; sched_lock_leave
;
; Leave a scheduler-critical section.
;
; Preserves: A, X, Y, P
; ------------------------------------------------------------

.proc sched_lock_leave
    php
    pha
    phx
    phy

    lda sched_lock
    beq @underflow

    dec sched_lock

    lda sched_lock_depth
    beq @depth_underflow

    dec sched_lock_depth
    lda sched_lock_depth
    beq @released_outermost

    ; DEBUG-BEGIN: temporary scheduler lock nested-leave diagnostic
    lda #DBG_SCHED_LOCK_LEAVE
    sta sched_lock_phase
    ; DEBUG-END: temporary scheduler lock nested-leave diagnostic
    bra @done

@released_outermost:
    ; DEBUG-BEGIN: temporary scheduler lock outer-release diagnostic
    lda #DBG_OWNER_NONE
    sta sched_lock_owner
    stz sched_lock_phase
    ; DEBUG-END: temporary scheduler lock outer-release diagnostic
    bra @done

@depth_underflow:
    ; The real lock byte was nonzero, but the diagnostic depth was
    ; already zero.  Record this as underflow and leave the decremented
    ; real lock byte in place.
    jsr @record_underflow
    bra @done

@underflow:
    jsr @record_underflow
    bra @done

@record_underflow:
    ; DEBUG-BEGIN: temporary scheduler lock underflow diagnostic
    lda #DBG_MARK_SCHED_LOCK_UNDERFLOW
    sta sched_debug_marker

    lda #DBG_SCHED_LOCK_BAD_LEAVE
    sta sched_lock_phase

    lda sched_lock_underflow
    cmp #$ff
    beq @uf_done
    inc sched_lock_underflow
    ; DEBUG-END: temporary scheduler lock underflow diagnostic
@uf_done:
    rts

@done:
    ply
    plx
    pla
    plp
    rts
.endproc
