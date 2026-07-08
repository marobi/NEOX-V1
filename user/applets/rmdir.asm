; ============================================================
; rmdir.asm
; NEOX nbox applet: rmdir
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_rmdir

.segment "USER_TEXT"

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

