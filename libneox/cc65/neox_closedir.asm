; ============================================================
; neox_closedir.asm
; NEOX libneox - cc65 public neox_closedir implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_closedir

.segment "C_BSS"

neox_closedir_args:
    .res CLOSEDIR_ARGS_SIZE

.segment "C_CODE"

.proc _neox_closedir
    sta neox_closedir_args+closedir_args::fd
    stz neox_closedir_args+closedir_args::reserved

    sei
    ldx #<neox_closedir_args
    ldy #>neox_closedir_args
    jsr sys_closedir
    bcs @failed

    lda #0
    tax
    rts

@failed:
    tya
    ldx #0
    rts
.endproc
