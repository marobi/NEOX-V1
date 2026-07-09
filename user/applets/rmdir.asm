; ============================================================
; rmdir.asm
; NEOX nbox applet: rmdir
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_rmdir
.export nbox_rmdir

.segment "USER_DATA"

nbox_rmdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE
.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_rmdir_msg_fail:
    .byte "RMDIR FAIL", 13
NBOX_RMDIR_MSG_FAIL_LEN = * - nbox_rmdir_msg_fail

.proc nbox_print_rmdir_fail
    lda #<nbox_rmdir_msg_fail
    ldx #>nbox_rmdir_msg_fail
    ldy #NBOX_RMDIR_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_rmdir
    jsr nbox_require_arg
    bcc @has_arg
    jmp nbox_print_arg_fail

@has_arg:
    SYSCALL nbox_rmdir_args, sys_rmdir
    bcc @ok
    jmp nbox_print_rmdir_fail
@ok:
    clc
    rts
.endproc

.proc nbox_cmd_rmdir
    jsr nbox_copy_arg_from_y
    jmp nbox_rmdir
.endproc

