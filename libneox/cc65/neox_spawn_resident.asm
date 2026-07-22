; ============================================================
; neox_spawn_resident.asm
; ============================================================

.setcpu "65C02"
.include "syscall.inc"

.export _neox_spawn_resident
.importzp c_sp
.importzp ptr1
.import incsp2

.segment "C_BSS"
neox_spawn_pid_out: .res 2
neox_spawn_status:  .res 1
neox_spawn_pid:     .res 1

.segment "C_CODE"

; <summary>
; Calls SYS_SPAWN_RESIDENT using the public C argument block.
; </summary>
.proc _neox_spawn_resident
    sta neox_spawn_pid_out
    stx neox_spawn_pid_out+1

    ldy #0
    lda (c_sp),y
    tax
    iny
    lda (c_sp),y
    tay

    sei
    jsr sys_spawn_resident
    bcs @failed

    sta neox_spawn_pid
    stz neox_spawn_status
    bra @store

@failed:
    tya
    sta neox_spawn_status
    lda #$FF
    sta neox_spawn_pid

@store:
    lda neox_spawn_pid_out
    ora neox_spawn_pid_out+1
    beq @return

    lda neox_spawn_pid_out
    sta ptr1
    lda neox_spawn_pid_out+1
    sta ptr1+1
    lda neox_spawn_pid
    sta (ptr1)

@return:
    lda neox_spawn_status
    ldx #0
    jmp incsp2
.endproc
