; ============================================================
; mv.asm
; NEOX nbox applet: mv
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_mv

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_mv
    jsr nbox_require_two_args
    bcc @has_args
    jmp nbox_print_arg_fail

@has_args:
    SYSCALL nbox_rename_args, sys_rename
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

