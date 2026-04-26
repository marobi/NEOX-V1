; ============================================================
; console_io.asm
; NEOX - getchar / putchar wrappers
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export getchar
.export putchar

.segment "BSS"

charbuf:
    .res 1

.segment "RODATA"

read_blk:
    .byte STDIN
    .byte 0
    .word charbuf
    .word 1

write_blk:
    .byte STDOUT
    .byte 0
    .word charbuf
    .word 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; getchar
;
; returns:
;   A = character
;   C = clear on success
;   C = set on error
; ------------------------------------------------------------

getchar:
gc_loop:
    SYSCALL read_blk, sys_read
    bcs gc_error

    ; AX = count
    cmp #0
    beq gc_loop

    lda charbuf
    clc
    rts

gc_error:
    sec
    rts

; ------------------------------------------------------------
; putchar
;
; input:
;   A = character
;
; returns:
;   C = clear on success
;   C = set on error
; ------------------------------------------------------------

putchar:
    sta charbuf

    SYSCALL write_blk, sys_write
    bcs pc_error

    clc
    rts

pc_error:
    sec
    rts
