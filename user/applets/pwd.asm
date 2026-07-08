; ============================================================
; pwd.asm
; NEOX nbox applet: pwd
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_pwd

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_pwd
    SYSCALL nbox_getcwd_args, sys_getcwd
    bcc @ok
    jmp nbox_print_unknown
@ok:
    ; A = length excluding NUL
    tay
    lda #<nbox_cwd_buf
    ldx #>nbox_cwd_buf
    jsr nbox_print_msg
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
; Command wrapper procedures.
.proc nbox_cmd_pwd
    jmp nbox_pwd
.endproc

