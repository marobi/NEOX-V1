; ============================================================
; neox_waitpid.asm
; ============================================================

.setcpu "65C02"
.include "syscall.inc"

.export _neox_waitpid
.importzp c_sp
.importzp ptr1
.import incsp1

.segment "C_BSS"
neox_wait_exit_ptr: .res 2
neox_wait_status:   .res 1
neox_wait_exit:     .res 1

.segment "C_CODE"

; <summary>
; Waits for and reaps one child.
; </summary>
.proc _neox_waitpid
    sta neox_wait_exit_ptr
    stx neox_wait_exit_ptr+1

    ldy #0
    lda (c_sp),y
    jsr sys_waitpid
    bcs @failed

    sta neox_wait_exit
    stz neox_wait_status
    bra @store

@failed:
    tya
    sta neox_wait_status
    stz neox_wait_exit

@store:
    lda neox_wait_exit_ptr
    ora neox_wait_exit_ptr+1
    beq @return

    lda neox_wait_exit_ptr
    sta ptr1
    lda neox_wait_exit_ptr+1
    sta ptr1+1
    lda neox_wait_exit
    sta (ptr1)

@return:
    lda neox_wait_status
    ldx #0
    jmp incsp1
.endproc
