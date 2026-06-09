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
.import current_pid
.import proc_exit_current
.import sched_yield

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
;   Context switching is IRQ-driven. After marking this process
;   dead, execution must not continue into user code, so this
;   routine waits for the next timer IRQ to switch away.
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
;   Scheduler switching is IRQ-only. This syscall is therefore a
;   stable ABI placeholder until syscall-side scheduling exists.
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
;   timer_start_current:
;       - allocates timer slot
;       - sets WAIT_TIMER
;       - marks process BLOCKED
; ------------------------------------------------------------

.proc ksys_sleep
    cmp #0
    beq @done

    jsr timer_start_current
    bcs @fail

    ; timer_start_current made current process PROC_BLOCKED.
    ; Now yield immediately using syscall-context scheduler path.
    jmp sched_yield

@fail:
    ldy #EAGAIN
    sec
    rts

@done:
    clc
    rts
.endproc
