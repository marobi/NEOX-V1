; ============================================================
; neox_readdir.asm
; NEOX libneox - cc65 public neox_readdir implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_readdir

.importzp c_sp
.importzp ptr1
.import incsp3

NEOX_READDIR_STACK_ENTRY_LO = 0
NEOX_READDIR_STACK_ENTRY_HI = 1
NEOX_READDIR_STACK_FD       = 2

.segment "C_BSS"

neox_readdir_args:
    .res READDIR_ARGS_SIZE

neox_readdir_end_ptr:
    .res 2

neox_readdir_end_value:
    .res 1

neox_readdir_status:
    .res 1

.segment "C_CODE"

.proc _neox_readdir
    sta neox_readdir_end_ptr
    stx neox_readdir_end_ptr+1

    ldy #NEOX_READDIR_STACK_FD
    lda (c_sp),y
    sta neox_readdir_args+readdir_args::fd
    stz neox_readdir_args+readdir_args::reserved

    ldy #NEOX_READDIR_STACK_ENTRY_LO
    lda (c_sp),y
    sta neox_readdir_args+readdir_args::entry_ptr
    iny
    lda (c_sp),y
    sta neox_readdir_args+readdir_args::entry_ptr+1

    lda #<DIR_ENTRY_SIZE
    sta neox_readdir_args+readdir_args::entry_size
    lda #>DIR_ENTRY_SIZE
    sta neox_readdir_args+readdir_args::entry_size+1

    stz neox_readdir_end_value

    sei
    ldx #<neox_readdir_args
    ldy #>neox_readdir_args
    jsr sys_readdir
    bcs @failed

    ; A/X == 0 marks end-of-directory.
    cpx #0
    bne @entry
    cmp #0
    bne @entry
    lda #1
    sta neox_readdir_end_value

@entry:
    stz neox_readdir_status
    bra @store_end

@failed:
    tya
    sta neox_readdir_status

@store_end:
    lda neox_readdir_end_ptr
    ora neox_readdir_end_ptr+1
    beq @return

    lda neox_readdir_end_ptr
    sta ptr1
    lda neox_readdir_end_ptr+1
    sta ptr1+1
    lda neox_readdir_end_value
    sta (ptr1)

@return:
    lda neox_readdir_status
    ldx #0
    jmp incsp3
.endproc
