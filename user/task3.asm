; ============================================================
; task3.asm
; NEOX console echo task
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "bios.inc"

T3_RX_FD          = STDIN
T3_TX_FD          = STDOUT

.export user_task3_entry

.segment "USER_DATA"

t3_byte:
    .res 1

t3_read_args:
    .byte T3_RX_FD
    .byte 0
    .word t3_byte
    .word 1

t3_write_args:
    .byte T3_TX_FD
    .byte 0
    .word t3_byte
    .word 1
	
.segment "USER_TEXT"

.proc user_task3_entry
@loop:
	SYSCALL t3_read_args, sys_read
    bcc @ok

	jsr sys_yield
    bra @loop

@ok:  
    SYSCALL t3_write_args, sys_write
	lda t3_byte
    cmp #'q'
    bne @loop

    jmp sys_exit
.endproc
