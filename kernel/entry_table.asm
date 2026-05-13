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
;   Padding ensures that KERN_TEXT always starts at $E030,
;   making binary dumps and disassembly match actual addresses.
; ============================================================

.setcpu "65C02"

.include "kernel.inc"

.export kernel_entry_table

.import kernel_main
.import set_brk_vector
.import enter_monitor_syscall
.import leave_monitor
.import ksys_read
.import ksys_write
.import ksys_exit
.import ksys_yield
.import ksys_sleep

.segment "KERNEL_ENTRY"

.assert * = KERNEL_BASE, error, "KERNEL_ENTRY must start at KERNEL_BASE"

RESET:
kernel_entry_table:
    jmp kernel_main
    jmp enter_monitor_syscall
	jmp set_brk_vector
	jmp leave_monitor
	jmp ksys_read
	jmp ksys_write
	jmp ksys_exit
	jmp ksys_yield
	jmp ksys_sleep
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
	.res 3, $00
