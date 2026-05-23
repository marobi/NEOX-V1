; ============================================================
; task3.asm
; NEOX console echo task
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "bios.inc"

.export user_task3_entry

.segment "USER_TEXT"

.proc user_task3_entry
@loop:
    jsr BIOS_GETCHAR
	
    jsr BIOS_PUTCHAR

    cmp #'q'
    bne @loop

    jmp sys_exit
.endproc
