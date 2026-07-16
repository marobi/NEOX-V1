; ============================================================
; echo.asm
; NEOX nbox applet: echo
;
; Initial behavior:
;   echo
;   echo arg0
;   echo arg0 arg1
;
; Arguments are separated by one space and output always ends in CR.
; Quoting, escapes, variables, and -n are intentionally not supported.
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_echo
.export nbox_echo

.segment "USER_TEXT"

; ------------------------------------------------------------
; nbox_echo
;
; Writes the resident launch arguments to stdout. The current command
; ABI supports up to two arguments.
; ------------------------------------------------------------
.proc nbox_echo
    lda nbox_arg_len
    beq @arg1

    lda #<nbox_arg_buf
    ldx #>nbox_arg_buf
    ldy nbox_arg_len
    jsr nbox_print_msg

@arg1:
    lda nbox_arg2_len
    beq @newline

    lda nbox_arg_len
    beq @print_arg1

    jsr nbox_print_space

@print_arg1:
    lda #<nbox_arg2_buf
    ldx #>nbox_arg2_buf
    ldy nbox_arg2_len
    jsr nbox_print_msg

@newline:
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
; nbox_cmd_echo
;
; Direct-dispatch wrapper. Child dispatch already receives copied launch
; arguments and calls nbox_echo directly.
; ------------------------------------------------------------
.proc nbox_cmd_echo
    jsr nbox_copy_two_args_from_y
    jmp nbox_echo
.endproc
