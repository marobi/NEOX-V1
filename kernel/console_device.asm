; ============================================================
; console_device.asm
; NEOX - console device operations
; ============================================================

.setcpu "65C02"

.include "fd.inc"
.include "syscall.inc"
.include "mailbox.inc"

.export console_ops

.import rp_console_read
.import rp_console_write

.segment "KERN_TEXT"

;
;
;
console_ops:
    .word console_read
    .word console_write
    .word console_ioctl
    .word console_close

;
;
;
.proc console_read
	lda RP_CONSOLE_RDY
	bne @has_data
	
	lda #0
	tax
	clc
	rts

@has_data:
    jmp rp_console_read
.endproc

;
;
;
.proc console_write
    jmp rp_console_write
.endproc

;
;
;
.proc console_ioctl
    ldy #ENOSYS
    sec
    rts
.endproc

;
;
;
.proc console_close
    clc
    rts
.endproc
