; ============================================================
; rm.asm
; NEOX nbox applet: rm
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_rm

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_rm
    jsr nbox_require_arg
    bcc @has_arg
    jmp nbox_print_arg_fail

@has_arg:
    SYSCALL nbox_delete_args, sys_delete
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

