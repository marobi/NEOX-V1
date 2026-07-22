; ============================================================
; neox_read.asm
; NEOX libneox - cc65 public neox_read implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_read

.importzp c_sp
.importzp ptr1
.import incsp5

NEOX_READ_STACK_REQUESTED_LO = 0
NEOX_READ_STACK_REQUESTED_HI = 1
NEOX_READ_STACK_BUFFER_LO    = 2
NEOX_READ_STACK_BUFFER_HI    = 3
NEOX_READ_STACK_FD           = 4

.segment "C_BSS"

neox_read_args:
    .res RW_ARGS_SIZE

neox_read_count_ptr:
    .res 2

neox_read_transferred:
    .res 2

neox_read_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_read
;
; Purpose:
;   Implements public neox_read() using the ordinary cc65 C ABI.
;
; Input:
;   A/X       = read_out pointer
;   (c_sp)+0  = requested low
;   (c_sp)+1  = requested high
;   (c_sp)+2  = buffer low
;   (c_sp)+3  = buffer high
;   (c_sp)+4  = fd
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_read
    sta neox_read_count_ptr
    stx neox_read_count_ptr+1

    ldy #NEOX_READ_STACK_FD
    lda (c_sp),y
    sta neox_read_args+rw_args::fd
    stz neox_read_args+rw_args::reserved

    ldy #NEOX_READ_STACK_BUFFER_LO
    lda (c_sp),y
    sta neox_read_args+rw_args::buf_ptr
    iny
    lda (c_sp),y
    sta neox_read_args+rw_args::buf_ptr+1

    ldy #NEOX_READ_STACK_REQUESTED_LO
    lda (c_sp),y
    sta neox_read_args+rw_args::len
    iny
    lda (c_sp),y
    sta neox_read_args+rw_args::len+1

    stz neox_read_transferred
    stz neox_read_transferred+1

    sei
    ldx #<neox_read_args
    ldy #>neox_read_args
    jsr sys_read
    bcs @failed

    sta neox_read_transferred
    stx neox_read_transferred+1
    stz neox_read_status
    bra @store_count

@failed:
    tya
    sta neox_read_status

@store_count:
    lda neox_read_count_ptr
    ora neox_read_count_ptr+1
    beq @return

    lda neox_read_count_ptr
    sta ptr1
    lda neox_read_count_ptr+1
    sta ptr1+1

    lda neox_read_transferred
    sta (ptr1)
    ldy #1
    lda neox_read_transferred+1
    sta (ptr1),y

@return:
    lda neox_read_status
    ldx #0
    jmp incsp5
.endproc
