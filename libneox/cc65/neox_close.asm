; ============================================================
; neox_close.asm
; NEOX libneox - cc65 public neox_close implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_close

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_close
;
; Input:
;   A = fd. X is ignored.
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_close
    sei
    jsr sys_close
    bcs @failed

    lda #0
    tax
    rts

@failed:
    tya
    ldx #0
    rts
.endproc
