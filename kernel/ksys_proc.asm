; ============================================================
; ksys_proc.asm
; NEOX - kernel-owned process lifecycle syscall services
;
; The syscall page only jumps here. Process lifecycle state is
; owned by the kernel, not by the syscall veneer.
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "syscall.inc"
.include "timer.inc"

.export ksys_exit
.export ksys_yield
.export ksys_sleep

.import idle_loop
.import proc_exit_current
.import sched_yield
.import sched_block_current

.import timer_start_current


.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_exit
;
; Input:
;   A = exit code
;
; Purpose:
;   Terminate the current process.
;
; Current scheduler model:
;   After marking this process dead, execution must not continue
;   into user code. Transfer to the idle loop until the scheduler
;   selects another runnable process.
; ------------------------------------------------------------

.proc ksys_exit
    jsr proc_exit_current

	jmp idle_loop
.endproc

; ------------------------------------------------------------
; ksys_yield
;
; Purpose:
;   Voluntary yield syscall.
;
; Current model:
;   Cooperative scheduling enters the same scheduler handoff path
;   used by preemptive scheduling.
; ------------------------------------------------------------

.proc ksys_yield
    jmp sched_yield
.endproc

; ------------------------------------------------------------
; ksys_sleep
;
; Input:
;   A = relative sleep ticks
;
; Purpose:
;   Block current process until timer expiration.
;
; Notes:
;   timer_start_current reserves and arms a timer slot only.
;   sched_block_current owns the actual process block transition.
; ------------------------------------------------------------

.proc ksys_sleep
    cmp #0
    beq @done

    jsr timer_start_current
    bcs @fail

    ; Y = armed timer slot.  The scheduler-owned block primitive
    ; saves the syscall continuation first, then commits WAIT_TIMER.
    lda #WAIT_TIMER
    jmp sched_block_current

@fail:
    ldy #EAGAIN
    sec
    rts

@done:
    clc
    rts
.endproc
