; ============================================================
; mkdir.asm
; NEOX nbox applet: mkdir
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_mkdir

.segment "USER_TEXT"

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

