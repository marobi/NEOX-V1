; ============================================================
; task6.asm
; NEOX - interactive nbox command loop
;
; Purpose:
;   Manual V38 command/app testing while task 5 remains the automated
;   filesystem regression runner. Task 3 remains unchanged.
;
; Commands are implemented in user/nbox.asm.
;
; Input policy for first interactive version:
;   - no local echo
;   - no backspace/delete processing
;   - collect normalized bytes until CR/LF
;   - dispatch one command line
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task6_entry

.import nbox_line_buf
.import nbox_line_len
.import nbox_dispatch_line
.import nbox_print_prompt

T6_RX_FD      = STDIN
T6_LINE_MAX   = 64

.segment "USER_DATA"

t6_byte:
    .res 1

t6_read_args:
    .byte T6_RX_FD
    .byte 0
    .word t6_byte
    .word 1

.segment "USER_TEXT"

; ------------------------------------------------------------
; t6_read_char
;
; Return:
;   C clear = one byte read into t6_byte
;   C set   = no byte / read failure
; ------------------------------------------------------------
.proc t6_read_char
    SYSCALL t6_read_args, sys_read
    bcc @ok
    sec
    rts
@ok:
    cmp #1
    bne @bad
    cpx #0
    bne @bad
    clc
    rts
@bad:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t6_uppercase_byte
; ------------------------------------------------------------
.proc t6_uppercase_byte
    lda t6_byte
    cmp #'a'
    bcc @done
    cmp #'z' + 1
    bcs @done
    sec
    sbc #$20
    sta t6_byte
@done:
    rts
.endproc

; ------------------------------------------------------------
; t6_finish_line
; ------------------------------------------------------------
.proc t6_finish_line
    ldx nbox_line_len
    lda #0
    sta nbox_line_buf,x
    jsr nbox_dispatch_line
    stz nbox_line_len
    jmp nbox_print_prompt
.endproc

; ------------------------------------------------------------
; t6_store_char
; ------------------------------------------------------------
.proc t6_store_char
    lda nbox_line_len
    cmp #T6_LINE_MAX - 1
    bcs @done

    tax
    lda t6_byte
    sta nbox_line_buf,x
    inc nbox_line_len
@done:
    rts
.endproc

.proc user_task6_entry
    stz nbox_line_len
    jsr nbox_print_prompt

@loop:
    jsr t6_read_char
    bcs @loop

    ; Normalize console input to 7-bit ASCII before parsing.
    lda t6_byte
    and #$7F
    sta t6_byte

    lda t6_byte
    cmp #13
    beq @newline
    cmp #10
    beq @newline

    jsr t6_uppercase_byte
    jsr t6_store_char
    bra @loop

@newline:
    jsr t6_finish_line
    bra @loop
.endproc
