; ============================================================
; test_read.asm
; NEOX - console read/write echo test
; ca65
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "../bios/bios.inc"

.export _user_entry

BUF_SIZE = 64

.segment "BSS"

buf:
    .res BUF_SIZE

.segment "RODATA"

read_blk:
    .byte STDIN          ; rw_args::fd
    .byte 0              ; rw_args::reserved
    .word buf            ; rw_args::buf_ptr
    .word BUF_SIZE       ; rw_args::len

write_blk:
    .byte STDOUT         ; rw_args::fd
    .byte 0              ; rw_args::reserved
    .word buf            ; rw_args::buf_ptr
    .word BUF_SIZE       ; rw_args::len       patched from XA

.segment "KERN_TEXT"

.proc _user_entry

@loop:
    SYSCALL read_blk, sys_read
    bcs @error

    ; X,A = bytes read
    cpx #0
    bne @echo
    cmp #0
    beq @loop

@echo:
	; copy length, buffer is same
    sta write_blk + rw_args::len
    stx write_blk + rw_args::len + 1

    SYSCALL write_blk, sys_write
    bcs @error

	lda #$0D
	jsr BIOS_PUTCHAR
    jmp @loop

@error:
    brk
	
.endproc
