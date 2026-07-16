; ============================================================
; device.asm
; NEOX - device dispatch layer
; ============================================================

.setcpu "65C02"

.include "fd.inc"
.include "syscall.inc"

.export dev_resolve_op

.import open_dev
.import console_ops
.import mul8u

.importzp dev_ptr

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Device ops pointer tables
;
; Index = DEV_*
; ------------------------------------------------------------

dev_ops:
    .word no_device_ops
    .word console_ops

.assert (DEV_MAX * DEV_OPS_ENTRY_SIZE) <= $100, error, "device operation pointer table exceeds 8-bit indexed range"

; ------------------------------------------------------------
; no_device_ops
; ------------------------------------------------------------

no_device_ops:
    .word dev_enodev
    .word dev_enodev
    .word dev_enodev
    .word dev_enodev

.proc dev_enodev
    ldy #ENODEV
    sec
    rts
.endproc

; ------------------------------------------------------------
; dev_resolve_op
;
; Input:
;   X = open object index
;   A = DEVOP_* offset
;
; Output:
;   C clear = ok
;   dev_ptr = resolved operation entry
;
;   C set = error
;   Y = errno
;
; Clobbers:
;   A, Y, dev_ptr
; ------------------------------------------------------------

.proc dev_resolve_op
    phx
    pha

    lda open_dev,x
    cmp #DEV_MAX
    bcc @dev_ok

    pla
    plx
    ldy #ENODEV
    sec
    rts

@dev_ok:
    ldx #DEV_OPS_ENTRY_SIZE
    jsr mul8u
    tay

    lda dev_ops,y
    sta dev_ptr
    lda dev_ops+1,y
    sta dev_ptr+1

    pla
    clc
    adc dev_ptr
    sta dev_ptr
    bcc :+
    inc dev_ptr+1
:

    ldy #0
    lda (dev_ptr),y
    pha
    iny
    lda (dev_ptr),y
    sta dev_ptr+1
    pla
    sta dev_ptr

    plx
    clc
    rts
.endproc

