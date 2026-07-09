; ============================================================
; help.asm
; NEOX nbox applet: help
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_help
.export nbox_help

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_help
    jmp nbox_print_help
.endproc

.proc nbox_cmd_help
    jmp nbox_help
.endproc

