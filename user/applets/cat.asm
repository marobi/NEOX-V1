; ============================================================
; cat.asm
; NEOX nbox applet: cat
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_cat

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_cat_close
    lda nbox_file_fd
    cmp #NBOX_FILE_FD_NONE
    beq @done

    pha
    lda #NBOX_FILE_FD_NONE
    sta nbox_file_fd
    sta nbox_cat_rw_args + rw_args::fd
    pla
    jsr sys_close
@done:
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cat
    jsr nbox_require_arg
    bcc @has_arg
    jmp nbox_print_arg_fail

@has_arg:
    SYSCALL nbox_open_args, sys_open
    bcc @opened
    jmp nbox_print_cat_fail

@opened:
    sta nbox_file_fd
    sta nbox_cat_rw_args + rw_args::fd

@read_loop:
    SYSCALL nbox_cat_rw_args, sys_read
    bcc @read_ok
    jsr nbox_cat_close
    jmp nbox_print_cat_fail

@read_ok:
    cmp #0
    bne @has_bytes
    cpx #0
    bne @has_bytes
    jsr nbox_cat_close
    clc
    rts

@has_bytes:
    ; The cat buffer is 64 bytes, so X should be zero.  Write A bytes.
    sta nbox_stdout_args + rw_args::len
    stz nbox_stdout_args + rw_args::len + 1
    lda #<nbox_cat_buf
    sta nbox_stdout_args + rw_args::buf_ptr
    lda #>nbox_cat_buf
    sta nbox_stdout_args + rw_args::buf_ptr + 1
    SYSCALL nbox_stdout_args, sys_write
    bcc @read_loop

    jsr nbox_cat_close
    jmp nbox_print_cat_fail
.endproc

.proc nbox_cmd_cat
    jsr nbox_copy_arg_from_y
    jmp nbox_cat
.endproc

