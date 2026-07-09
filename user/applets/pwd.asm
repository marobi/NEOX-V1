; ============================================================
; pwd.asm
; NEOX nbox applet: pwd
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_pwd
.export nbox_pwd

.segment "USER_DATA"

nbox_pwd_getcwd_args:
    .word nbox_cwd_buf
    .word NBOX_PATH_MAX
    .word 0
    .byte NEOX_PATH_FLAGS_NONE
    .byte 0
.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_pwd
    SYSCALL nbox_pwd_getcwd_args, sys_getcwd
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

