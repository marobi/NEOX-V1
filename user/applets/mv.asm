; ============================================================
; mv.asm
; NEOX nbox applet: mv
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_mv
.export nbox_mv

.segment "USER_DATA"

nbox_mv_rename_args:
    .word nbox_arg_buf
    .word nbox_arg2_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte FS_PATH_FLAGS_NONE
.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_mv_msg_fail:
    .byte "MV FAIL", 13
NBOX_MV_MSG_FAIL_LEN = * - nbox_mv_msg_fail

.proc nbox_print_mv_fail
    lda #<nbox_mv_msg_fail
    ldx #>nbox_mv_msg_fail
    ldy #NBOX_MV_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_mv
    jsr nbox_require_two_args
    bcc @has_args
    jmp nbox_print_arg_fail

@has_args:
    SYSCALL nbox_mv_rename_args, sys_rename
    bcc @ok
    jmp nbox_print_mv_fail
@ok:
    clc
    rts
.endproc

.proc nbox_cmd_mv
    jsr nbox_copy_two_args_from_y
    jmp nbox_mv
.endproc

