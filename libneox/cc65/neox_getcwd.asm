; ============================================================
; neox_getcwd.asm
; NEOX libneox - cc65 public neox_getcwd implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_getcwd

.importzp c_sp
.importzp ptr1
.import incsp4

NEOX_GETCWD_STACK_SIZE_LO   = 0
NEOX_GETCWD_STACK_SIZE_HI   = 1
NEOX_GETCWD_STACK_BUFFER_LO = 2
NEOX_GETCWD_STACK_BUFFER_HI = 3

.segment "C_BSS"

neox_getcwd_args:
    .res GETCWD_ARGS_SIZE

neox_getcwd_length_ptr:
    .res 2

neox_getcwd_result_length:
    .res 2

neox_getcwd_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_getcwd
;
; Input:
;   A/X       = length_out pointer
;   (c_sp)+0  = buffer_size low
;   (c_sp)+1  = buffer_size high
;   (c_sp)+2  = buffer pointer low
;   (c_sp)+3  = buffer pointer high
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_getcwd
    sta neox_getcwd_length_ptr
    stx neox_getcwd_length_ptr+1

    ldy #NEOX_GETCWD_STACK_BUFFER_LO
    lda (c_sp),y
    sta neox_getcwd_args+getcwd_args::buffer_ptr
    iny
    lda (c_sp),y
    sta neox_getcwd_args+getcwd_args::buffer_ptr+1

    ldy #NEOX_GETCWD_STACK_SIZE_LO
    lda (c_sp),y
    sta neox_getcwd_args+getcwd_args::buffer_size
    iny
    lda (c_sp),y
    sta neox_getcwd_args+getcwd_args::buffer_size+1

    stz neox_getcwd_args+getcwd_args::result_len
    stz neox_getcwd_args+getcwd_args::result_len+1
    stz neox_getcwd_args+getcwd_args::flags
    stz neox_getcwd_args+getcwd_args::reserved

    stz neox_getcwd_result_length
    stz neox_getcwd_result_length+1

    sei
    ldx #<neox_getcwd_args
    ldy #>neox_getcwd_args
    jsr sys_getcwd
    bcs @failed

    sta neox_getcwd_result_length
    stx neox_getcwd_result_length+1
    stz neox_getcwd_status
    bra @store_length

@failed:
    tya
    sta neox_getcwd_status

@store_length:
    lda neox_getcwd_length_ptr
    ora neox_getcwd_length_ptr+1
    beq @return

    lda neox_getcwd_length_ptr
    sta ptr1
    lda neox_getcwd_length_ptr+1
    sta ptr1+1

    lda neox_getcwd_result_length
    sta (ptr1)
    ldy #1
    lda neox_getcwd_result_length+1
    sta (ptr1),y

@return:
    lda neox_getcwd_status
    ldx #0
    jmp incsp4
.endproc
