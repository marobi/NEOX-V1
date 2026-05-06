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

.export ksys_exit
.export ksys_yield

.import idle_loop
.import current_pid
.import proc_exit_current

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
    clc
    rts
.endproc
