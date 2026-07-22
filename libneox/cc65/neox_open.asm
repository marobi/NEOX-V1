; ============================================================
; neox_open.asm
; NEOX libneox - cc65 public neox_open implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_open

.importzp c_sp
.importzp ptr1
.import incsp3

NEOX_OPEN_STACK_MODE    = 0
NEOX_OPEN_STACK_PATH_LO = 1
NEOX_OPEN_STACK_PATH_HI = 2

NEOX_OPEN_PATH_MAX = 64

.segment "C_BSS"

neox_open_args:
    .res OPEN_ARGS_SIZE

neox_open_fd_ptr:
    .res 2

neox_open_result_fd:
    .res 1

neox_open_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_open
;
; Input:
;   A/X       = fd_out pointer
;   (c_sp)+0  = mode
;   (c_sp)+1  = path low
;   (c_sp)+2  = path high
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_open
    sta neox_open_fd_ptr
    stx neox_open_fd_ptr+1

    ldy #NEOX_OPEN_STACK_PATH_LO
    lda (c_sp),y
    sta neox_open_args+open_args::path_ptr
    iny
    lda (c_sp),y
    sta neox_open_args+open_args::path_ptr+1

    lda #<NEOX_OPEN_PATH_MAX
    sta neox_open_args+open_args::max_len
    lda #>NEOX_OPEN_PATH_MAX
    sta neox_open_args+open_args::max_len+1

    ldy #NEOX_OPEN_STACK_MODE
    lda (c_sp),y
    sta neox_open_args+open_args::flags
    stz neox_open_args+open_args::device

    stz neox_open_result_fd

    sei
    ldx #<neox_open_args
    ldy #>neox_open_args
    jsr sys_open
    bcs @failed

    sta neox_open_result_fd
    stz neox_open_status
    bra @store_fd

@failed:
    tya
    sta neox_open_status

@store_fd:
    lda neox_open_fd_ptr
    ora neox_open_fd_ptr+1
    beq @return

    lda neox_open_fd_ptr
    sta ptr1
    lda neox_open_fd_ptr+1
    sta ptr1+1
    lda neox_open_result_fd
    sta (ptr1)

@return:
    lda neox_open_status
    ldx #0
    jmp incsp3
.endproc
