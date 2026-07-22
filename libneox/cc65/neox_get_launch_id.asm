; ============================================================
; neox_get_launch_id.asm
; ============================================================

.setcpu "65C02"
.include "syscall.inc"

.export _neox_get_launch_id
.importzp ptr1

.segment "C_BSS"
neox_launch_id_ptr: .res 2
neox_launch_id_status: .res 1
neox_launch_id_value: .res 1

.segment "C_CODE"

.proc _neox_get_launch_id
    sta neox_launch_id_ptr
    stx neox_launch_id_ptr+1

    jsr sys_get_launch_id
    bcs @failed

    sta neox_launch_id_value
    stz neox_launch_id_status
    bra @store

@failed:
    tya
    sta neox_launch_id_status
    lda #$FF
    sta neox_launch_id_value

@store:
    lda neox_launch_id_ptr
    ora neox_launch_id_ptr+1
    beq @return

    lda neox_launch_id_ptr
    sta ptr1
    lda neox_launch_id_ptr+1
    sta ptr1+1
    lda neox_launch_id_value
    sta (ptr1)

@return:
    lda neox_launch_id_status
    ldx #0
    rts
.endproc
