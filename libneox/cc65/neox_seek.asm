; ============================================================
; neox_seek.asm
; ============================================================

.setcpu "65C02"
.include "syscall.inc"

.export _neox_seek
.importzp c_sp
.importzp ptr1
.import incsp6

.segment "C_BSS"
neox_seek_args: .res SEEK_ARGS_SIZE
neox_seek_position_ptr: .res 2
neox_seek_status: .res 1

.segment "C_CODE"

; Stack: +0 whence, +1..+4 offset, +5 fd.
.proc _neox_seek
    sta neox_seek_position_ptr
    stx neox_seek_position_ptr+1

    ldy #5
    lda (c_sp),y
    sta neox_seek_args+seek_args::fd

    ldy #0
    lda (c_sp),y
    sta neox_seek_args+seek_args::whence

    ldy #1
    lda (c_sp),y
    sta neox_seek_args+seek_args::offset_lo
    iny
    lda (c_sp),y
    sta neox_seek_args+seek_args::offset_lo+1
    iny
    lda (c_sp),y
    sta neox_seek_args+seek_args::offset_hi
    iny
    lda (c_sp),y
    sta neox_seek_args+seek_args::offset_hi+1

    stz neox_seek_args+seek_args::result_lo
    stz neox_seek_args+seek_args::result_lo+1
    stz neox_seek_args+seek_args::result_hi
    stz neox_seek_args+seek_args::result_hi+1

    sei
    ldx #<neox_seek_args
    ldy #>neox_seek_args
    jsr sys_seek
    bcs @failed

    stz neox_seek_status
    bra @store

@failed:
    tya
    sta neox_seek_status

@store:
    lda neox_seek_position_ptr
    ora neox_seek_position_ptr+1
    beq @return

    lda neox_seek_position_ptr
    sta ptr1
    lda neox_seek_position_ptr+1
    sta ptr1+1

    ldy #0
    lda neox_seek_args+seek_args::result_lo
    sta (ptr1),y
    iny
    lda neox_seek_args+seek_args::result_lo+1
    sta (ptr1),y
    iny
    lda neox_seek_args+seek_args::result_hi
    sta (ptr1),y
    iny
    lda neox_seek_args+seek_args::result_hi+1
    sta (ptr1),y

@return:
    lda neox_seek_status
    ldx #0
    jmp incsp6
.endproc
