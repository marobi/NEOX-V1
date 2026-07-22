; ============================================================
; neox_signal.asm
; NEOX libneox - cc65 signal syscall wrapper
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_signal

.importzp c_sp
.import incsp1

.segment "C_BSS"

neox_signal_number:
    .res 1

neox_signal_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_signal
;
; C prototype:
;   neox_status_t neox_signal(neox_pid_t pid, uint8_t signal);
;
; Input:
;   A        = signal (rightmost argument)
;   (c_sp)+0 = target PID
;
; Return:
;   A = NEOX status
;   X = 0
; ------------------------------------------------------------
.proc _neox_signal
    sta neox_signal_number

    ldy #0
    lda (c_sp),y
    tax

    lda neox_signal_number
    jsr sys_signal
    bcs @failed

    stz neox_signal_status
    bra @return

@failed:
    tya
    sta neox_signal_status

@return:
    lda neox_signal_status
    ldx #0
    jmp incsp1
.endproc
