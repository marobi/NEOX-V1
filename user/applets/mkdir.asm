; ============================================================
; mkdir.asm
; NEOX nbox applet: mkdir
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_mkdir
.export nbox_mkdir

.segment "USER_DATA"

nbox_mkdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE
.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_mkdir_msg_fail:
    .byte "MKDIR FAIL", 13
NBOX_MKDIR_MSG_FAIL_LEN = * - nbox_mkdir_msg_fail

.proc nbox_print_mkdir_fail
    lda #<nbox_mkdir_msg_fail
    ldx #>nbox_mkdir_msg_fail
    ldy #NBOX_MKDIR_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_mkdir
    jsr nbox_require_arg
    bcc @has_arg
    jmp nbox_print_arg_fail

@has_arg:
    SYSCALL nbox_mkdir_args, sys_mkdir
    bcc @ok
    jmp nbox_print_mkdir_fail
@ok:
    clc
    rts
.endproc

.proc nbox_cmd_mkdir
    jsr nbox_copy_arg_from_y
    jmp nbox_mkdir
.endproc

