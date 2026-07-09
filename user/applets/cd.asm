; ============================================================
; cd.asm
; NEOX nbox applet: cd
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_cd
.export nbox_cd

.segment "USER_DATA"

nbox_cd_chdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE
.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_cd_msg_fail:
    .byte "CD FAIL", 13
NBOX_CD_MSG_FAIL_LEN = * - nbox_cd_msg_fail

.proc nbox_print_cd_fail
    lda #<nbox_cd_msg_fail
    ldx #>nbox_cd_msg_fail
    ldy #NBOX_CD_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_cd
    jsr nbox_default_arg_root_if_empty
    SYSCALL nbox_cd_chdir_args, sys_chdir
    bcc @ok
    jmp nbox_print_cd_fail
@ok:
    clc
    rts
.endproc

.proc nbox_cmd_cd
    jsr nbox_copy_arg_from_y
    jmp nbox_cd
.endproc

