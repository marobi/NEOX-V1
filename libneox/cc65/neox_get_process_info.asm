; ============================================================
; neox_get_process_info.asm
; NEOX libneox - cc65 public process-information wrapper
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_get_process_info

.importzp c_sp
.import incsp1

NEOX_GET_PROCESS_INFO_STACK_PID = 0

.segment "C_BSS"

neox_get_process_info_args:
    .res PROCINFO_ARGS_SIZE

neox_get_process_info_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_get_process_info
;
; Input:
;   A/X      = info pointer
;   (c_sp)+0 = pid
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_get_process_info
    sta neox_get_process_info_args+procinfo_args::buffer_ptr
    stx neox_get_process_info_args+procinfo_args::buffer_ptr+1

    ldy #NEOX_GET_PROCESS_INFO_STACK_PID
    lda (c_sp),y
    sta neox_get_process_info_args+procinfo_args::pid

    stz neox_get_process_info_args+procinfo_args::reserved

    lda #<PROCINFO_RECORD_SIZE
    sta neox_get_process_info_args+procinfo_args::buffer_size
    lda #>PROCINFO_RECORD_SIZE
    sta neox_get_process_info_args+procinfo_args::buffer_size+1

    sei
    ldx #<neox_get_process_info_args
    ldy #>neox_get_process_info_args
    jsr sys_getprocinfo
    bcs @failed

    stz neox_get_process_info_status
    bra @return

@failed:
    tya
    sta neox_get_process_info_status

@return:
    lda neox_get_process_info_status
    ldx #0
    jmp incsp1
.endproc
