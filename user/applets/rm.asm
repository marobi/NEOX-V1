; ============================================================
; rm.asm
; NEOX nbox applet: rm
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_rm
.export nbox_rm

.segment "USER_DATA"

nbox_rm_delete_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte FS_PATH_FLAGS_NONE
.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_rm_msg_fail:
    .byte "RM FAIL", 13
NBOX_RM_MSG_FAIL_LEN = * - nbox_rm_msg_fail

.proc nbox_print_rm_fail
    lda #<nbox_rm_msg_fail
    ldx #>nbox_rm_msg_fail
    ldy #NBOX_RM_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_rm
    jsr nbox_require_arg
    bcc @has_arg
    jmp nbox_print_arg_fail

@has_arg:
    SYSCALL nbox_rm_delete_args, sys_delete
    bcc @ok
    jmp nbox_print_rm_fail
@ok:
    clc
    rts
.endproc

.proc nbox_cmd_rm
    jsr nbox_copy_arg_from_y
    jmp nbox_rm
.endproc

