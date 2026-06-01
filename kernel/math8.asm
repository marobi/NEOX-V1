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

.proc mul8u_core
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

; ------------------------------------------------------------
; mul8u
;
; Input:
;   A = multiplicand
;   X = multiplier
;
; Output:
;   A       = product low
;   X       = product high
;   factor1 = product low
;   factor2 = product high
;
; Clobbers:
;   Y
;
; Notes:
;   Preemption-safe public wrapper.
;
;   The internal multiply core uses global zero-page scratch:
;       factor1
;       factor2
;
;   IRQs are disabled while operands/results are live in that
;   shared scratch.
; ------------------------------------------------------------

.proc mul8u
    php
    sei

    sta factor1
    stx factor2

    jsr mul8u_core

    lda factor1
    ldx factor2

    plp
    rts
.endproc
