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
.export scheduler_tick
.export timer_alloc
.export timer_free
.export timer_start_current
.export scheduler_wake_timers

.import current_pid
.import proc_state
.import wait_reason

.import system_ticks_lo
.import system_ticks_hi

.import timer_pid
.import timer_until_lo
.import timer_until_hi

.import proc_set_wait
.import proc_wake

.import proc_ticks_lo
.import proc_ticks_hi
.import idle_ticks_lo
.import idle_ticks_hi

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
    stz system_ticks_lo
    stz system_ticks_hi

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
; scheduler_tick
;
; Purpose:
;   Increment global 16-bit scheduler tick counter.
;
; Called from:
;   timer IRQ path, once per scheduler tick.
; ------------------------------------------------------------

.proc scheduler_tick
    inc system_ticks_lo
    bne @done

    inc system_ticks_hi

@done:
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
;   C clear = current process blocked on WAIT_TIMER
;   C set   = no timer slot available
;
; Purpose:
;   Allocate a timer slot for current_pid and block the current
;   process until:
;
;       system_ticks + A
;
; Notes:
;   - A = 0 is treated as success/no block by the caller.
;   - wait_object stores the timer slot.
;   - Uses 16-bit absolute wake time.
; ------------------------------------------------------------

.proc timer_start_current
    ; Preserve requested duration.
    pha

    jsr timer_alloc
    bcc @slot_ok

    ; No slot available.
    pla
    sec
    rts

@slot_ok:
    ; Save allocated slot in Y for wait_object.
    txa
    tay

    ; Mark timer slot as owned by current process.
    lda current_pid
    sta timer_pid,x

    ; Compute absolute wake tick:
    ;   wake = system_ticks + duration
    pla
    clc
    adc system_ticks_lo
    sta timer_until_lo,x

    lda system_ticks_hi
    adc #0
    sta timer_until_hi,x

    ; Block current process on WAIT_TIMER.
    ldx current_pid
    lda #WAIT_TIMER
    ; Y already contains timer slot.
    jsr proc_set_wait

    clc
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

    ; Preserve sleeping PID while doing time comparison.
    pha

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

    bmi @restore

    ; --------------------------------------------------------
    ; Timer expired.
    ; --------------------------------------------------------

    pla
    tay                 ; Y = sleeping PID

    ; Free timer slot before waking the process.
    phx
    jsr timer_free
    plx

    ; Wake stored PID if it is still blocked on WAIT_TIMER.
    tya
    tax

    lda proc_state,x
    cmp #PROC_BLOCKED
    bne @restart_scan

    lda wait_reason,x
    cmp #WAIT_TIMER
    bne @restart_scan

    jsr proc_wake

@restart_scan:
    ; proc_wake may clobber X.
    ; Restarting is simple and safe because MAX_TIMER is small.
    ldx #0
    bra @scan

@restore:
    ; Timer not expired; discard preserved PID.
    pla

@next:
    inx
    bra @scan

@done:
    rts
.endproc
