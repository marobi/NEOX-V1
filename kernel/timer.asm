; ============================================================
; timer.asm
; NEOX - scheduler timer wait subsystem
;
; Purpose:
;   Provides timer-based blocking for sys_sleep and future
;   timeout-based waits.
;
; Model:
;   - system_ticks is a 16-bit tick counter incremented once per
;     timer IRQ.
;   - sleeping processes use WAIT_TIMER.
;   - wait_object[pid] stores the timer slot index.
;   - timer_pid[slot] stores the PID attached to that slot.
;
; Ownership:
;   - shared_state.asm owns storage
;   - timer.asm owns timer-slot logic
;   - scheduler.asm calls scheduler_tick / scheduler_wake_timers
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "timer.inc"

.export timer_init
.export timer_alloc
.export timer_free
.export timer_start_current
.export timer_commit_current
.export scheduler_wake_timers

.import active_pid
.import proc_state
.import wait_reason
.import wait_object


.import timer_pid
.import timer_until_lo
.import timer_until_hi

.import proc_wake

.import system_ticks_lo
.import system_ticks_hi

.segment "KERN_BSS"

; Timer wake scratch.  scheduler_wake_timers is called only from
; scheduler-owned paths while scheduler serialization is active.
timer_scan_slot_tmp:
    .res 1

timer_scan_pid_tmp:
    .res 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; timer_init
;
; Purpose:
;   Initialize global tick counter and timer wait table.
;
; Called from:
;   kernel initialization.
; ------------------------------------------------------------

.proc timer_init
    ldx #0

@clear:
    lda #TIMER_NONE
    sta timer_pid,x

    stz timer_until_lo,x
    stz timer_until_hi,x

    inx
    cpx #MAX_TIMER
    bne @clear

    rts
.endproc

; ------------------------------------------------------------
; timer_alloc
;
; Purpose:
;   Allocate a free timer slot.
;
; Output:
;   C clear = success
;             X = timer slot
;
;   C set   = no free timer slot
;
; Notes:
;   The slot is not marked used here. Caller fills timer_pid.
; ------------------------------------------------------------

.proc timer_alloc
    ldx #0

@scan:
    cpx #MAX_TIMER
    bcs @fail

    lda timer_pid,x
    cmp #TIMER_NONE
    beq @found

    inx
    bra @scan

@found:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; timer_free
;
; Input:
;   X = timer slot
;
; Purpose:
;   Release a timer slot.
; ------------------------------------------------------------

.proc timer_free
    lda #TIMER_NONE
    sta timer_pid,x

    stz timer_until_lo,x
    stz timer_until_hi,x

    rts
.endproc

; ------------------------------------------------------------
; timer_start_current
;
; Input:
;   A = relative sleep ticks
;
; Output:
;   C clear = timer slot armed for active_pid
;             Y = timer slot
;
;   C set   = no timer slot available
;
; Purpose:
;   Reserve and arm a timer slot for active_pid.  This routine does
;   not mark the process blocked.  The scheduler-owned block primitive
;   commits WAIT_TIMER after the syscall continuation has been saved.
;
; Race rule:
;   The slot is attached to active_pid before IRQs are restored.
;   scheduler_wake_timers only wakes a process if wait_object[pid]
;   matches this exact timer slot.  If a very short timer expires
;   before the process commits WAIT_TIMER, the slot is freed as stale
;   and sys_sleep returns as already elapsed.
; ------------------------------------------------------------

.proc timer_start_current
    php
    sei
    pha                         ; saved duration, above saved P

    jsr timer_alloc
    bcc @slot_ok

    ; No slot available: discard saved duration and restore caller P.
    pla
    plp
    sec
    rts

@slot_ok:
    ; Save allocated slot in Y for wait_object.
    txa
    tay

    ; Attach the slot to the current process.  The process is not
    ; blocked yet; scheduler_wake_timers verifies wait_object before
    ; waking, and frees expired non-matching slots as stale.
    lda active_pid
    sta timer_pid,x

    ; Compute absolute wake tick:
    ;   wake = system_ticks + duration
    pla                         ; A = saved duration
    clc
    adc system_ticks_lo
    sta timer_until_lo,x

    lda system_ticks_hi
    adc #0
    sta timer_until_hi,x

    plp
    clc
    rts
.endproc

; ------------------------------------------------------------
; timer_commit_current
;
; Input:
;   X = armed timer slot
;
; Output:
;   C clear = slot is still attached to active_pid and still pending
;   C set   = slot is invalid or already expired/freed
;
; Purpose:
;   Validate that the armed timer slot still belongs to active_pid and
;   has not already expired before sched_block_current commits
;   WAIT_TIMER.  If the timer is already due, free the slot and let
;   sys_sleep return success immediately instead of blocking on a timer
;   that should already have elapsed.
; ------------------------------------------------------------

.proc timer_commit_current
    cpx #MAX_TIMER
    bcs @fail

    lda timer_pid,x
    cmp active_pid
    bne @fail

    ; Use the same signed 16-bit expiry test as scheduler_wake_timers:
    ;   expired if signed(system_ticks - timer_until) >= 0
    sec
    lda system_ticks_lo
    sbc timer_until_lo,x

    lda system_ticks_hi
    sbc timer_until_hi,x
    bmi @pending

    ; The timer elapsed before the block transition committed.
    ; Free the slot and report "already elapsed" to sched_block_current.
    jsr timer_free
    sec
    rts

@pending:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; scheduler_wake_timers
;
; Purpose:
;   Wake processes whose timer wait has expired.
;
; Model:
;   timer_pid[slot] identifies the sleeping process.
;   wait_object[pid] contains the timer slot index.
;
; Expiry test:
;   Uses signed 16-bit difference:
;
;       expired if signed(system_ticks - timer_until) >= 0
;
;   This is safe across 16-bit wraparound as long as one sleep
;   interval is less than $8000 ticks.
;
; Clobbers:
;   A, X, Y
; ------------------------------------------------------------

.proc scheduler_wake_timers
    ldx #0

@scan:
    cpx #MAX_TIMER
    bcs @done

    lda timer_pid,x
    cmp #TIMER_NONE
    beq @next

    sta timer_scan_pid_tmp
    stx timer_scan_slot_tmp

    ; --------------------------------------------------------
    ; Overflow-safe expiry check:
    ;
    ;   delta = system_ticks - timer_until
    ;
    ; If delta high byte has bit 7 set, the timer target is
    ; still in the future.
    ; --------------------------------------------------------

    sec
    lda system_ticks_lo
    sbc timer_until_lo,x

    lda system_ticks_hi
    sbc timer_until_hi,x

    bmi @next

    ; --------------------------------------------------------
    ; Timer expired.  Wake only if the stored PID is still blocked
    ; on WAIT_TIMER for this exact timer slot.  Mismatched expired
    ; slots are stale and are freed without waking anything.
    ; --------------------------------------------------------

    ldx timer_scan_pid_tmp

    lda proc_state,x
    cmp #PROC_BLOCKED
    bne @free_stale

    lda wait_reason,x
    cmp #WAIT_TIMER
    bne @free_stale

    lda wait_object,x
    cmp timer_scan_slot_tmp
    bne @free_stale

    ; Exact owner match: free slot, then wake the process.
    ; Continue from the following timer slot afterwards.  proc_wake may
    ; clobber X, so reload the saved slot index explicitly.
    ldx timer_scan_slot_tmp
    jsr timer_free

    ldx timer_scan_pid_tmp
    jsr proc_wake

    ldx timer_scan_slot_tmp
    inx
    bra @scan

@free_stale:
    ldx timer_scan_slot_tmp
    jsr timer_free

    ldx timer_scan_slot_tmp
    inx
    bra @scan

@next:
    inx
    bra @scan

@done:
    rts
.endproc
