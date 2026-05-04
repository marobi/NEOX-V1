; kernel/math8.asm

.setcpu "65C02"

.importzp factor1
.importzp factor2

.export mul8u

.segment "KERN_TEXT"

; ------------------------------------------------------------
; mul8u
;
; Purpose:
;   Unsigned 8x8 multiply.
;
; Input:
;   factor1 = multiplicand
;   factor2 = multiplier
;
; Output:
;   factor1 = product low
;   factor2 = product high
;
; Clobbers:
;   A, X, C
;
; Notes:
;   Destructive: original factors are overwritten.
; ------------------------------------------------------------

.proc mul8u
    lda #$00
    ldx #$08

    lsr factor1

@loop:
    bcc @no_add

    clc
    adc factor2

@no_add:
    ror a
    ror factor1

    dex
    bne @loop

    sta factor2
    rts
.endproc
