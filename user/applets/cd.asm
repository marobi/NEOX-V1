; ============================================================
; cd.asm
; NEOX nbox applet: cd
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_cd

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_cd
    jsr nbox_default_arg_root_if_empty
    SYSCALL nbox_chdir_args, sys_chdir
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

