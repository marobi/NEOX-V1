; ============================================================
; task3.asm
; NEOX console echo task
;
; Policy:
;   User tasks must use the normal syscall console path.
;
; Behavior:
;   - read one byte from STDIN
;   - echo it to STDOUT
;   - exit when the byte is 'Q'
;   - blocking console read/write are handled by the kernel
;   - exit on read/write error or short transfer
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

T3_RX_FD          = STDIN
T3_TX_FD          = STDOUT

.export user_task3_entry

.segment "USER_DATA"

t3_byte:
    .res 1

t3_read_args:
    .byte T3_RX_FD
    .byte 0
    .word t3_byte
    .word 1

t3_write_args:
    .byte T3_TX_FD
    .byte 0
    .word t3_byte
    .word 1

.segment "USER_TEXT"

; ------------------------------------------------------------
; t3_read_char
;
; Return:
;   C clear = one byte read into t3_byte
;   C set   = read error or short transfer
; ------------------------------------------------------------

.proc t3_read_char
    SYSCALL t3_read_args, sys_read
    bcc @ok

    sec
    rts

@ok:
    cmp #1
    bne @bad_count

    cpx #0
    bne @bad_count

    clc
    rts

@bad_count:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t3_write_char
;
; Return:
;   C clear = one byte written from t3_byte
;   C set   = write error or short transfer
; ------------------------------------------------------------

.proc t3_write_char
    SYSCALL t3_write_args, sys_write
    bcc @ok

    sec
    rts

@ok:
    cmp #1
    bne @bad_count

    cpx #0
    bne @bad_count

    clc
    rts

@bad_count:
    sec
    rts
.endproc

; ------------------------------------------------------------
; user_task3_entry
; ------------------------------------------------------------

.proc user_task3_entry
@loop:
    jsr t3_read_char
    bcs @exit

    jsr t3_write_char
    bcs @exit

    lda t3_byte
    cmp #'Q'
    bne @loop

@exit:
    jmp sys_exit
.endproc
