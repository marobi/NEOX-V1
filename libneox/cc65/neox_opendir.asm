; ============================================================
; neox_opendir.asm
; NEOX libneox - cc65 public neox_opendir implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_opendir

.importzp c_sp
.importzp ptr1
.import incsp2

NEOX_OPENDIR_STACK_PATH_LO = 0
NEOX_OPENDIR_STACK_PATH_HI = 1
NEOX_OPENDIR_PATH_MAX = 64

.segment "C_BSS"

neox_opendir_args:
    .res OPENDIR_ARGS_SIZE

neox_opendir_fd_ptr:
    .res 2

neox_opendir_result_fd:
    .res 1

neox_opendir_status:
    .res 1

.segment "C_CODE"

.proc _neox_opendir
    sta neox_opendir_fd_ptr
    stx neox_opendir_fd_ptr+1

    ldy #NEOX_OPENDIR_STACK_PATH_LO
    lda (c_sp),y
    sta neox_opendir_args+opendir_args::path_ptr
    iny
    lda (c_sp),y
    sta neox_opendir_args+opendir_args::path_ptr+1

    lda #<NEOX_OPENDIR_PATH_MAX
    sta neox_opendir_args+opendir_args::max_len
    lda #>NEOX_OPENDIR_PATH_MAX
    sta neox_opendir_args+opendir_args::max_len+1
    stz neox_opendir_args+opendir_args::device
    stz neox_opendir_args+opendir_args::flags

    stz neox_opendir_result_fd

    sei
    ldx #<neox_opendir_args
    ldy #>neox_opendir_args
    jsr sys_opendir
    bcs @failed

    sta neox_opendir_result_fd
    stz neox_opendir_status
    bra @store_fd

@failed:
    tya
    sta neox_opendir_status

@store_fd:
    lda neox_opendir_fd_ptr
    ora neox_opendir_fd_ptr+1
    beq @return

    lda neox_opendir_fd_ptr
    sta ptr1
    lda neox_opendir_fd_ptr+1
    sta ptr1+1
    lda neox_opendir_result_fd
    sta (ptr1)

@return:
    lda neox_opendir_status
    ldx #0
    jmp incsp2
.endproc
