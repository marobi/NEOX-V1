; ============================================================
; cp.asm
; NEOX nbox applet: cp
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_cp

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc nbox_cp_close_src
    lda nbox_cp_src_fd
    cmp #NBOX_FILE_FD_NONE
    beq @done

    pha
    lda #NBOX_FILE_FD_NONE
    sta nbox_cp_src_fd
    sta nbox_cp_read_args + rw_args::fd
    pla
    jsr sys_close
@done:
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cp_close_dst
    lda nbox_cp_dst_fd
    cmp #NBOX_FILE_FD_NONE
    beq @done

    pha
    lda #NBOX_FILE_FD_NONE
    sta nbox_cp_dst_fd
    sta nbox_cp_write_args + rw_args::fd
    pla
    jsr sys_close
@done:
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cp_fail
    jsr nbox_cp_close_src
    jsr nbox_cp_close_dst
    jmp nbox_print_cp_fail
.endproc

; ------------------------------------------------------------
.proc nbox_cp_try_dst_dir
    lda #NBOX_DIR_FD_NONE
    sta nbox_dir_fd
    sta nbox_closedir_args + closedir_args::fd

    SYSCALL nbox_cp_dst_opendir_args, sys_opendir
    bcc @opened
    sec
    rts

@opened:
    sta nbox_dir_fd
    sta nbox_closedir_args + closedir_args::fd
    jsr nbox_ls_close_dir
    clc
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cp_find_src_basename
    stz nbox_src_idx
    ldy #0
@loop:
    lda nbox_arg_buf,y
    beq @done
    cmp #'/'
    beq @separator
    cmp #':'
    beq @separator
    iny
    bra @loop

@separator:
    iny
    sty nbox_src_idx
    bra @loop

@done:
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cp_append_basename_to_dst_dir
    jsr nbox_cp_find_src_basename

    ldy nbox_src_idx
    lda nbox_arg_buf,y
    bne @basename_ok
    sec
    rts

@basename_ok:
    ldy nbox_arg2_len
    beq @need_slash
    dey
    lda nbox_arg2_buf,y
    iny
    cmp #'/'
    beq @copy_basename

@need_slash:
    cpy #NBOX_PATH_MAX - 1
    bcs @fail
    lda #'/'
    sta nbox_arg2_buf,y
    iny
    sty nbox_arg2_len

@copy_basename:
    sty nbox_dst_idx

@copy_loop:
    ldy nbox_src_idx
    lda nbox_arg_buf,y
    beq @done

    ldy nbox_dst_idx
    cpy #NBOX_PATH_MAX - 1
    bcs @fail
    sta nbox_arg2_buf,y

    inc nbox_src_idx
    inc nbox_dst_idx
    bra @copy_loop

@done:
    ldy nbox_dst_idx
    lda #0
    sta nbox_arg2_buf,y
    sty nbox_arg2_len
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_cp
    jsr nbox_require_two_args
    bcc @has_args
    jmp nbox_print_arg_fail

@has_args:
    lda #NBOX_FILE_FD_NONE
    sta nbox_cp_src_fd
    sta nbox_cp_dst_fd
    sta nbox_cp_read_args + rw_args::fd
    sta nbox_cp_write_args + rw_args::fd

    jsr nbox_cp_try_dst_dir
    bcs @dst_path_ready

    jsr nbox_cp_append_basename_to_dst_dir
    bcc @dst_path_ready
    jmp nbox_print_cp_fail

@dst_path_ready:
    SYSCALL nbox_cp_src_open_args, sys_open
    bcc @src_opened
    jmp nbox_print_cp_fail

@src_opened:
    sta nbox_cp_src_fd
    sta nbox_cp_read_args + rw_args::fd

    SYSCALL nbox_cp_dst_open_args, sys_open
    bcc @dst_opened
    jsr nbox_cp_close_src
    jmp nbox_print_cp_fail

@dst_opened:
    sta nbox_cp_dst_fd
    sta nbox_cp_write_args + rw_args::fd

@read_loop:
    lda #NBOX_CAT_BUF_SIZE
    sta nbox_cp_read_args + rw_args::len
    stz nbox_cp_read_args + rw_args::len + 1

    SYSCALL nbox_cp_read_args, sys_read
    bcc @read_ok
    jmp nbox_cp_fail

@read_ok:
    cmp #0
    bne @has_bytes
    cpx #0
    bne @has_bytes

    jsr nbox_cp_close_src
    jsr nbox_cp_close_dst
    clc
    rts

@has_bytes:
    ; The copy buffer is 64 bytes, so X should be zero.
    cpx #0
    beq @write_chunk
    jmp nbox_cp_fail

@write_chunk:
    sta nbox_cp_write_args + rw_args::len
    stz nbox_cp_write_args + rw_args::len + 1

    SYSCALL nbox_cp_write_args, sys_write
    bcc @write_ok
    jmp nbox_cp_fail

@write_ok:
    cmp nbox_cp_write_args + rw_args::len
    beq @write_hi_check
    jmp nbox_cp_fail
@write_hi_check:
    cpx nbox_cp_write_args + rw_args::len + 1
    beq @read_loop
    jmp nbox_cp_fail
.endproc

.proc nbox_cmd_cp
    jsr nbox_copy_two_args_from_y
    jmp nbox_cp
.endproc

