; ============================================================
; entry_table.asm
; NEOX - fixed kernel entry table
;
; Purpose:
;   Provides stable entry points at the start of the kernel
;   image for other images (syscall layer, BIOS, etc.).
;
; Layout:
;   - Located at $E000
;
; Notes:
;   Padding ensures that KERN_TEXT always starts at $8060
; ============================================================

.setcpu "65C02"

.include "kernel.inc"

.export kernel_entry_table

.import kernel_main
.import set_brk_vector
.import enter_monitor
.import leave_monitor
.import ksys_read
.import ksys_write
.import ksys_exit
.import ksys_yield
.import ksys_sleep
.import ksys_close
.import ksys_dup
.import ksys_dup2
.import ksys_pipe
.import pipe_create_between_fd
.import ksys_ticks
.import ksys_signal
.import ksys_open

.segment "KERNEL_ENTRY"

.assert * = KERNEL_BASE, error, "KERNEL_ENTRY must start at KERNEL_BASE"

RESET:
kernel_entry_table:
    jmp kernel_main
    jmp enter_monitor
	jmp set_brk_vector
	jmp leave_monitor
	jmp ksys_read
	jmp ksys_write
	jmp ksys_exit
	jmp ksys_yield
	jmp ksys_sleep
	jmp ksys_close
	jmp ksys_dup
	jmp ksys_dup2
	jmp ksys_pipe
	jmp pipe_create_between_fd
	jmp ksys_ticks
	jmp ksys_signal
    jmp ksys_open
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
