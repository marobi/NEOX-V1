; ============================================================
; nbox.asm
; NEOX - small BusyBox-like applet collection for user space
;
; V38e applets:
;   help
;   pwd
;   cd [path]
;   ls [path]
;   cat path
;   rm path
;   mv old new
;   mkdir path
;   rmdir path
;   cp source dest
;   ps
;
; Parser contract:
;   - command plus up to two arguments
;   - input line should be clean command text
;   - nbox uppercases command tokens, but does not own prompt/input editing
;   - spaces and tabs separate command and arguments
;   - no quotes, wildcards, redirection, or pipes
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "process.inc"

.export nbox_line_buf
.export nbox_line_len
.export nbox_dispatch_line

NBOX_LINE_MAX      = 64
NBOX_PATH_MAX      = 64
NBOX_CMD_NAME_MAX  = 5
NBOX_CMD_NAME_SLOT = 6
NBOX_DIR_FD_NONE   = $FF
NBOX_FILE_FD_NONE  = $FF
NBOX_ATTR_DIR      = $10
NBOX_CAT_BUF_SIZE  = 64

NBOX_PROCINFO_PID   = 0
NBOX_PROCINFO_PPID  = 1
NBOX_PROCINFO_STATE = 2
NBOX_PROCINFO_WAIT  = 3
NBOX_PROCINFO_SIG   = 4

.segment "USER_DATA"

nbox_line_buf:
    .res NBOX_LINE_MAX

nbox_line_len:
    .byte 0

nbox_arg_buf:
    .res NBOX_PATH_MAX

nbox_arg2_buf:
    .res NBOX_PATH_MAX

nbox_arg_len:
    .byte 0

nbox_arg2_len:
    .byte 0

nbox_cwd_buf:
    .res NBOX_PATH_MAX

nbox_dir_entry:
    .res DIR_ENTRY_SIZE

nbox_cat_buf:
    .res NBOX_CAT_BUF_SIZE

nbox_dir_fd:
    .byte NBOX_DIR_FD_NONE

nbox_file_fd:
    .byte NBOX_FILE_FD_NONE

nbox_cp_src_fd:
    .byte NBOX_FILE_FD_NONE

nbox_cp_dst_fd:
    .byte NBOX_FILE_FD_NONE

nbox_cmd_idx:
    .byte 0

nbox_src_idx:
    .byte 0

nbox_dst_idx:
    .byte 0

nbox_name_offset:
    .byte 0

nbox_jmpvec:
    .word 0

nbox_cmd_buf:
    .res NBOX_CMD_NAME_SLOT

nbox_ps_pid:
    .byte 0

nbox_procinfo_buf:
    .res PROCINFO_RECORD_SIZE

nbox_hex_byte:
    .byte 0

nbox_hex_buf:
    .res 2

nbox_type_prefix:
    .byte "- "

nbox_cr:
    .byte 13

nbox_msg_help:
    .byte "COMMANDS: HELP PWD CD LS CAT RM MV MKDIR RMDIR CP PS", 13
NBOX_MSG_HELP_LEN = * - nbox_msg_help

nbox_msg_unknown:
    .byte "?", 13
NBOX_MSG_UNKNOWN_LEN = * - nbox_msg_unknown

nbox_msg_cd_fail:
    .byte "CD FAIL", 13
NBOX_MSG_CD_FAIL_LEN = * - nbox_msg_cd_fail

nbox_msg_ls_fail:
    .byte "LS FAIL", 13
NBOX_MSG_LS_FAIL_LEN = * - nbox_msg_ls_fail

nbox_msg_readdir_fail:
    .byte "READDIR FAIL", 13
NBOX_MSG_READDIR_FAIL_LEN = * - nbox_msg_readdir_fail

nbox_msg_cat_fail:
    .byte "CAT FAIL", 13
NBOX_MSG_CAT_FAIL_LEN = * - nbox_msg_cat_fail

nbox_msg_rm_fail:
    .byte "RM FAIL", 13
NBOX_MSG_RM_FAIL_LEN = * - nbox_msg_rm_fail

nbox_msg_mv_fail:
    .byte "MV FAIL", 13
NBOX_MSG_MV_FAIL_LEN = * - nbox_msg_mv_fail

nbox_msg_mkdir_fail:
    .byte "MKDIR FAIL", 13
NBOX_MSG_MKDIR_FAIL_LEN = * - nbox_msg_mkdir_fail

nbox_msg_rmdir_fail:
    .byte "RMDIR FAIL", 13
NBOX_MSG_RMDIR_FAIL_LEN = * - nbox_msg_rmdir_fail

nbox_msg_cp_fail:
    .byte "CP FAIL", 13
NBOX_MSG_CP_FAIL_LEN = * - nbox_msg_cp_fail

nbox_msg_ps_fail:
    .byte "PS FAIL", 13
NBOX_MSG_PS_FAIL_LEN = * - nbox_msg_ps_fail

nbox_msg_ps_header:
    .byte "PID PPID ST  WAIT SIG", 13
NBOX_MSG_PS_HEADER_LEN = * - nbox_msg_ps_header

nbox_space:
    .byte " "

nbox_hex_digits:
    .byte "0123456789ABCDEF"

nbox_ps_state_empty:
    .byte "EMP"
nbox_ps_state_new:
    .byte "NEW"
nbox_ps_state_ready:
    .byte "RDY"
nbox_ps_state_running:
    .byte "RUN"
nbox_ps_state_blocked:
    .byte "BLK"
nbox_ps_state_stopped:
    .byte "STP"
nbox_ps_state_zombie:
    .byte "ZOM"
nbox_ps_state_unknown:
    .byte "???"

nbox_ps_wait_none:
    .byte "----"
nbox_ps_wait_console:
    .byte "CON "
nbox_ps_wait_device:
    .byte "DEV "
nbox_ps_wait_pipe_read:
    .byte "PIPR"
nbox_ps_wait_timer:
    .byte "TIMR"
nbox_ps_wait_proc:
    .byte "PROC"
nbox_ps_wait_lock:
    .byte "LOCK"
nbox_ps_wait_pipe_write:
    .byte "PIPW"
nbox_ps_wait_unknown:
    .byte "????"

nbox_msg_arg_fail:
    .byte "ARG?", 13
NBOX_MSG_ARG_FAIL_LEN = * - nbox_msg_arg_fail

nbox_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

nbox_getcwd_args:
    .word nbox_cwd_buf
    .word NBOX_PATH_MAX
    .word 0
    .byte NEOX_PATH_FLAGS_NONE
    .byte 0

nbox_chdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_opendir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_readdir_args:
    .byte NBOX_DIR_FD_NONE
    .byte 0
    .word nbox_dir_entry
    .word DIR_ENTRY_SIZE

nbox_closedir_args:
    .byte NBOX_DIR_FD_NONE
    .byte 0

nbox_open_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte OPEN_READ
    .byte 0

nbox_cat_rw_args:
    .byte NBOX_FILE_FD_NONE
    .byte 0
    .word nbox_cat_buf
    .word NBOX_CAT_BUF_SIZE

nbox_cp_src_open_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte OPEN_READ
    .byte 0

nbox_cp_dst_open_args:
    .word nbox_arg2_buf
    .word NBOX_PATH_MAX
    .byte OPEN_WRITE_TRUNC
    .byte 0

nbox_cp_dst_opendir_args:
    .word nbox_arg2_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_cp_read_args:
    .byte NBOX_FILE_FD_NONE
    .byte 0
    .word nbox_cat_buf
    .word NBOX_CAT_BUF_SIZE

nbox_cp_write_args:
    .byte NBOX_FILE_FD_NONE
    .byte 0
    .word nbox_cat_buf
    .word 0

nbox_delete_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte FS_PATH_FLAGS_NONE

nbox_rename_args:
    .word nbox_arg_buf
    .word nbox_arg2_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte FS_PATH_FLAGS_NONE

nbox_mkdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_rmdir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_procinfo_args:
    .byte 0
    .byte 0
    .word nbox_procinfo_buf
    .word PROCINFO_RECORD_SIZE

.segment "USER_TEXT"

; ------------------------------------------------------------
; nbox_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = length
; ------------------------------------------------------------
.proc nbox_print_msg
    sta nbox_stdout_args + rw_args::buf_ptr
    stx nbox_stdout_args + rw_args::buf_ptr + 1

    tya
    sta nbox_stdout_args + rw_args::len
    stz nbox_stdout_args + rw_args::len + 1

    SYSCALL nbox_stdout_args, sys_write
    rts
.endproc

.proc nbox_print_cr
    lda #<nbox_cr
    ldx #>nbox_cr
    ldy #1
    jmp nbox_print_msg
.endproc

.proc nbox_print_help
    lda #<nbox_msg_help
    ldx #>nbox_msg_help
    ldy #NBOX_MSG_HELP_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_unknown
    lda #<nbox_msg_unknown
    ldx #>nbox_msg_unknown
    ldy #NBOX_MSG_UNKNOWN_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_arg_fail
    lda #<nbox_msg_arg_fail
    ldx #>nbox_msg_arg_fail
    ldy #NBOX_MSG_ARG_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_cd_fail
    lda #<nbox_msg_cd_fail
    ldx #>nbox_msg_cd_fail
    ldy #NBOX_MSG_CD_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_ls_fail
    lda #<nbox_msg_ls_fail
    ldx #>nbox_msg_ls_fail
    ldy #NBOX_MSG_LS_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_readdir_fail
    lda #<nbox_msg_readdir_fail
    ldx #>nbox_msg_readdir_fail
    ldy #NBOX_MSG_READDIR_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_cat_fail
    lda #<nbox_msg_cat_fail
    ldx #>nbox_msg_cat_fail
    ldy #NBOX_MSG_CAT_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_rm_fail
    lda #<nbox_msg_rm_fail
    ldx #>nbox_msg_rm_fail
    ldy #NBOX_MSG_RM_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_mv_fail
    lda #<nbox_msg_mv_fail
    ldx #>nbox_msg_mv_fail
    ldy #NBOX_MSG_MV_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_mkdir_fail
    lda #<nbox_msg_mkdir_fail
    ldx #>nbox_msg_mkdir_fail
    ldy #NBOX_MSG_MKDIR_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_rmdir_fail
    lda #<nbox_msg_rmdir_fail
    ldx #>nbox_msg_rmdir_fail
    ldy #NBOX_MSG_RMDIR_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_cp_fail
    lda #<nbox_msg_cp_fail
    ldx #>nbox_msg_cp_fail
    ldy #NBOX_MSG_CP_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_ps_fail
    lda #<nbox_msg_ps_fail
    ldx #>nbox_msg_ps_fail
    ldy #NBOX_MSG_PS_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_space
    lda #<nbox_space
    ldx #>nbox_space
    ldy #1
    jmp nbox_print_msg
.endproc

.proc nbox_print_hex_byte
    sta nbox_hex_byte

    lsr
    lsr
    lsr
    lsr
    tax
    lda nbox_hex_digits,x
    sta nbox_hex_buf

    lda nbox_hex_byte
    and #$0F
    tax
    lda nbox_hex_digits,x
    sta nbox_hex_buf+1

    lda #<nbox_hex_buf
    ldx #>nbox_hex_buf
    ldy #2
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
; nbox_copy_arg_from_y
;
; Input:
;   Y = offset just after command token
;
; Output:
;   nbox_arg_buf contains optional argument, NUL-terminated
;   nbox_arg_len contains byte length excluding NUL
; ------------------------------------------------------------
.proc nbox_copy_arg_from_y
@skip:
    lda nbox_line_buf,y
    cmp #' '
    beq @next_skip
    cmp #9
    beq @next_skip
    bra @copy_start
@next_skip:
    iny
    bra @skip

@copy_start:
    sty nbox_src_idx
    stz nbox_dst_idx

@copy_loop:
    ldy nbox_src_idx
    lda nbox_line_buf,y
    bne @not_done
    jmp @done
@not_done:
    cmp #' '
    beq @done
    cmp #9
    beq @done

    ldy nbox_dst_idx
    cpy #NBOX_PATH_MAX - 1
    bcs @done
    sta nbox_arg_buf,y

    inc nbox_dst_idx
    inc nbox_src_idx
    bra @copy_loop

@done:
    ldy nbox_dst_idx
    lda #0
    sta nbox_arg_buf,y
    sty nbox_arg_len
    rts
.endproc

; ------------------------------------------------------------
; nbox_copy_two_args_from_y
;
; Input:
;   Y = offset just after command token
;
; Output:
;   nbox_arg_buf/nbox_arg2_buf contain first/second argument
; ------------------------------------------------------------
.proc nbox_copy_two_args_from_y
    jsr nbox_copy_arg_from_y

    ; Advance Y to end of first argument from the stored source start.
    ldy nbox_src_idx
@first_end:
    lda nbox_line_buf,y
    beq @no_second
    cmp #' '
    beq @skip_second_blanks
    cmp #9
    beq @skip_second_blanks
    iny
    bra @first_end

@skip_second_blanks:
    lda nbox_line_buf,y
    cmp #' '
    beq @skip_one
    cmp #9
    beq @skip_one
    bra @second_start
@skip_one:
    iny
    bra @skip_second_blanks

@second_start:
    sty nbox_src_idx
    stz nbox_dst_idx

@copy2_loop:
    ldy nbox_src_idx
    lda nbox_line_buf,y
    beq @copy2_done
    cmp #' '
    beq @copy2_done
    cmp #9
    beq @copy2_done

    ldy nbox_dst_idx
    cpy #NBOX_PATH_MAX - 1
    bcs @copy2_done
    sta nbox_arg2_buf,y

    inc nbox_dst_idx
    inc nbox_src_idx
    bra @copy2_loop

@copy2_done:
    ldy nbox_dst_idx
    lda #0
    sta nbox_arg2_buf,y
    sty nbox_arg2_len
    rts

@no_second:
    stz nbox_arg2_buf
    stz nbox_arg2_len
    rts
.endproc

.proc nbox_require_arg
    lda nbox_arg_len
    beq @missing
    clc
    rts
@missing:
    sec
    rts
.endproc

.proc nbox_require_two_args
    lda nbox_arg_len
    beq @missing
    lda nbox_arg2_len
    beq @missing
    clc
    rts
@missing:
    sec
    rts
.endproc

.proc nbox_default_arg_dot_if_empty
    lda nbox_arg_len
    bne @done
    lda #'.'
    sta nbox_arg_buf
    stz nbox_arg_buf+1
    lda #1
    sta nbox_arg_len
@done:
    rts
.endproc

.proc nbox_default_arg_root_if_empty
    lda nbox_arg_len
    bne @done
    lda #'/'
    sta nbox_arg_buf
    stz nbox_arg_buf+1
    lda #1
    sta nbox_arg_len
@done:
    rts
.endproc

; ------------------------------------------------------------
; nbox_strlen_dirent_name
;
; Return:
;   Y = length of nbox_dir_entry.name, capped at DIR_ENTRY_NAME_SIZE
; ------------------------------------------------------------
.proc nbox_strlen_dirent_name
    ldy #0
@loop:
    cpy #DIR_ENTRY_NAME_SIZE
    bcs @done
    lda nbox_dir_entry + dir_entry::name,y
    beq @done
    iny
    bra @loop
@done:
    rts
.endproc

; ------------------------------------------------------------
; nbox_pwd
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
; nbox_cd
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

; ------------------------------------------------------------
; nbox_ls_print_entry
; ------------------------------------------------------------
.proc nbox_ls_print_entry
    lda #'-'
    ldx nbox_dir_entry + dir_entry::attr
    txa
    and #NBOX_ATTR_DIR
    beq @type_ready
    lda #'d'
@type_ready:
    sta nbox_type_prefix

    lda #<nbox_type_prefix
    ldx #>nbox_type_prefix
    ldy #2
    jsr nbox_print_msg

    jsr nbox_strlen_dirent_name
    tya
    beq @cr_only
    tay
    lda #<(nbox_dir_entry + dir_entry::name)
    ldx #>(nbox_dir_entry + dir_entry::name)
    jsr nbox_print_msg
@cr_only:
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
; nbox_ls_close_dir
;
; Close the currently-open directory handle.  The close result is ignored
; because this helper is used on both normal EOF and error cleanup paths.
; ------------------------------------------------------------
.proc nbox_ls_close_dir
    lda nbox_dir_fd
    cmp #NBOX_DIR_FD_NONE
    beq @done

    SYSCALL nbox_closedir_args, sys_closedir
    lda #NBOX_DIR_FD_NONE
    sta nbox_dir_fd
    sta nbox_readdir_args + readdir_args::fd
    sta nbox_closedir_args + closedir_args::fd
@done:
    rts
.endproc

; ------------------------------------------------------------
; nbox_ls_pass_dirs
;
; First LS pass: print directory entries only, preserving the original
; directory order inside the directory group.
;
; Return:
;   C clear = success
;   C set   = failure
;   A = 1   = opendir failed
;   A = 2   = readdir failed
; ------------------------------------------------------------
.proc nbox_ls_pass_dirs
    SYSCALL nbox_opendir_args, sys_opendir
    bcc @opened
    lda #1
    sec
    rts

@opened:
    sta nbox_dir_fd
    sta nbox_readdir_args + readdir_args::fd
    sta nbox_closedir_args + closedir_args::fd

@loop:
    SYSCALL nbox_readdir_args, sys_readdir
    bcc @read_ok

    jsr nbox_ls_close_dir
    lda #2
    sec
    rts

@read_ok:
    cmp #0
    bne @entry
    cpx #0
    bne @entry

    jsr nbox_ls_close_dir
    clc
    rts

@entry:
    lda nbox_dir_entry + dir_entry::attr
    and #NBOX_ATTR_DIR
    beq @loop

    jsr nbox_ls_print_entry
    bra @loop
.endproc

; ------------------------------------------------------------
; nbox_ls_pass_files
;
; Second LS pass: print non-directory entries only, preserving the original
; directory order inside the file group.
;
; Return:
;   C clear = success
;   C set   = failure
;   A = 1   = opendir failed
;   A = 2   = readdir failed
; ------------------------------------------------------------
.proc nbox_ls_pass_files
    SYSCALL nbox_opendir_args, sys_opendir
    bcc @opened
    lda #1
    sec
    rts

@opened:
    sta nbox_dir_fd
    sta nbox_readdir_args + readdir_args::fd
    sta nbox_closedir_args + closedir_args::fd

@loop:
    SYSCALL nbox_readdir_args, sys_readdir
    bcc @read_ok

    jsr nbox_ls_close_dir
    lda #2
    sec
    rts

@read_ok:
    cmp #0
    bne @entry
    cpx #0
    bne @entry

    jsr nbox_ls_close_dir
    clc
    rts

@entry:
    lda nbox_dir_entry + dir_entry::attr
    and #NBOX_ATTR_DIR
    bne @loop

    jsr nbox_ls_print_entry
    bra @loop
.endproc

; ------------------------------------------------------------
; nbox_ls
;
; List directories first, then files.  No alphabetic sorting is done;
; original directory order is preserved within each group.
; ------------------------------------------------------------
.proc nbox_ls
    jsr nbox_default_arg_dot_if_empty

    jsr nbox_ls_pass_dirs
    bcc @files
    cmp #2
    beq @readdir_fail
    jmp nbox_print_ls_fail

@files:
    jsr nbox_ls_pass_files
    bcc @ok
    cmp #2
    beq @readdir_fail
    jmp nbox_print_ls_fail

@readdir_fail:
    jmp nbox_print_readdir_fail

@ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; nbox_cat_close
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
; nbox_cat
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

; ------------------------------------------------------------
; nbox_rm
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

; ------------------------------------------------------------
; nbox_mv
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

; ------------------------------------------------------------
; nbox_mkdir
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

; ------------------------------------------------------------
; nbox_rmdir
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

; ------------------------------------------------------------
; nbox_cp_close_src
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
; nbox_cp_close_dst
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
; nbox_cp_fail
; ------------------------------------------------------------
.proc nbox_cp_fail
    jsr nbox_cp_close_src
    jsr nbox_cp_close_dst
    jmp nbox_print_cp_fail
.endproc

; ------------------------------------------------------------
; nbox_cp_try_dst_dir
;
; Probe whether the second CP argument names an existing directory.
;
; Return:
;   C clear = destination is an existing directory
;   C set   = destination is not openable as a directory
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
; nbox_cp_find_src_basename
;
; Find the final component of the source path.  Slash and colon are
; treated as component separators so paths such as 0:/DIR/FILE.TXT and
; 0:FILE.TXT both produce FILE.TXT.
;
; Output:
;   nbox_src_idx = offset of basename inside nbox_arg_buf
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
; nbox_cp_append_basename_to_dst_dir
;
; Convert CP destination directory argument into a file path by appending
; the source basename:
;
;   CP WRITE.TXT TEST
;
; becomes:
;
;   TEST/WRITE.TXT
;
; Return:
;   C clear = path built in nbox_arg2_buf
;   C set   = source basename empty or destination buffer overflow
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
; nbox_cp
;
; Copy source file to destination file.  If the destination names an
; existing directory, append the source basename and copy into that
; directory, e.g. CP WRITE.TXT TEST -> TEST/WRITE.TXT.
; The implementation uses a fixed 64-byte user-space buffer.
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

; ------------------------------------------------------------
; nbox_clear_cmd_buf
; ------------------------------------------------------------
.proc nbox_clear_cmd_buf
    stz nbox_cmd_buf
    stz nbox_cmd_buf+1
    stz nbox_cmd_buf+2
    stz nbox_cmd_buf+3
    stz nbox_cmd_buf+4
    stz nbox_cmd_buf+5
    rts
.endproc

; ------------------------------------------------------------
; nbox_copy_command_token
;
; Input:
;   Y = command token start
;
; Output:
;   C clear = command copied
;   C set   = command too long
;   nbox_cmd_buf = zero-padded uppercase command token
;   nbox_line_idx = offset just after command token
; ------------------------------------------------------------
nbox_line_idx:
    .byte 0

.proc nbox_copy_command_token
    jsr nbox_clear_cmd_buf
    stz nbox_dst_idx

@loop:
    lda nbox_line_buf,y
    beq @done
    cmp #' '
    beq @done
    cmp #9
    beq @done

    ldx nbox_dst_idx
    cpx #NBOX_CMD_NAME_MAX
    bcs @too_long

    and #$7F
    cmp #'a'
    bcc @upper_ready
    cmp #'z' + 1
    bcs @upper_ready
    sec
    sbc #$20
@upper_ready:
    sta nbox_cmd_buf,x
    inc nbox_dst_idx
    iny
    bra @loop

@done:
    sty nbox_line_idx
    clc
    rts

@too_long:
    sec
    rts
.endproc

; ------------------------------------------------------------
; nbox_command_matches_at_x
;
; Input:
;   X = byte offset into nbox_cmd_names
;
; Return:
;   C clear = match
;   C set   = no match
; ------------------------------------------------------------
.proc nbox_command_matches_at_x
    lda nbox_cmd_buf
    cmp nbox_cmd_names,x
    bne @no
    inx
    lda nbox_cmd_buf+1
    cmp nbox_cmd_names,x
    bne @no
    inx
    lda nbox_cmd_buf+2
    cmp nbox_cmd_names,x
    bne @no
    inx
    lda nbox_cmd_buf+3
    cmp nbox_cmd_names,x
    bne @no
    inx
    lda nbox_cmd_buf+4
    cmp nbox_cmd_names,x
    bne @no
    inx
    lda nbox_cmd_buf+5
    cmp nbox_cmd_names,x
    bne @no

    clc
    rts
@no:
    sec
    rts
.endproc

; ------------------------------------------------------------
; nbox_ps_print_state
;
; Input:
;   A = process state byte
; ------------------------------------------------------------
.proc nbox_ps_print_state
    cmp #PROC_EMPTY
    beq @empty
    cmp #PROC_NEW
    beq @new
    cmp #PROC_READY
    beq @ready
    cmp #PROC_RUNNING
    beq @running
    cmp #PROC_BLOCKED
    beq @blocked
    cmp #PROC_STOPPED
    beq @stopped
    cmp #PROC_ZOMBIE
    beq @zombie
    lda #<nbox_ps_state_unknown
    ldx #>nbox_ps_state_unknown
    ldy #3
    jmp nbox_print_msg
@empty:
    lda #<nbox_ps_state_empty
    ldx #>nbox_ps_state_empty
    ldy #3
    jmp nbox_print_msg
@new:
    lda #<nbox_ps_state_new
    ldx #>nbox_ps_state_new
    ldy #3
    jmp nbox_print_msg
@ready:
    lda #<nbox_ps_state_ready
    ldx #>nbox_ps_state_ready
    ldy #3
    jmp nbox_print_msg
@running:
    lda #<nbox_ps_state_running
    ldx #>nbox_ps_state_running
    ldy #3
    jmp nbox_print_msg
@blocked:
    lda #<nbox_ps_state_blocked
    ldx #>nbox_ps_state_blocked
    ldy #3
    jmp nbox_print_msg
@stopped:
    lda #<nbox_ps_state_stopped
    ldx #>nbox_ps_state_stopped
    ldy #3
    jmp nbox_print_msg
@zombie:
    lda #<nbox_ps_state_zombie
    ldx #>nbox_ps_state_zombie
    ldy #3
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
; nbox_ps_print_wait
;
; Input:
;   A = wait reason byte
; ------------------------------------------------------------
.proc nbox_ps_print_wait
    cmp #WAIT_NONE
    beq @none
    cmp #WAIT_CONSOLE
    beq @console
    cmp #WAIT_DEVICE
    beq @device
    cmp #WAIT_PIPE_READ
    beq @pipe_read
    cmp #WAIT_TIMER
    beq @timer
    cmp #WAIT_PROC
    beq @proc
    cmp #WAIT_LOCK
    beq @lock
    cmp #WAIT_PIPE_WRITE
    beq @pipe_write
    lda #<nbox_ps_wait_unknown
    ldx #>nbox_ps_wait_unknown
    ldy #4
    jmp nbox_print_msg
@none:
    lda #<nbox_ps_wait_none
    ldx #>nbox_ps_wait_none
    ldy #4
    jmp nbox_print_msg
@console:
    lda #<nbox_ps_wait_console
    ldx #>nbox_ps_wait_console
    ldy #4
    jmp nbox_print_msg
@device:
    lda #<nbox_ps_wait_device
    ldx #>nbox_ps_wait_device
    ldy #4
    jmp nbox_print_msg
@pipe_read:
    lda #<nbox_ps_wait_pipe_read
    ldx #>nbox_ps_wait_pipe_read
    ldy #4
    jmp nbox_print_msg
@timer:
    lda #<nbox_ps_wait_timer
    ldx #>nbox_ps_wait_timer
    ldy #4
    jmp nbox_print_msg
@proc:
    lda #<nbox_ps_wait_proc
    ldx #>nbox_ps_wait_proc
    ldy #4
    jmp nbox_print_msg
@lock:
    lda #<nbox_ps_wait_lock
    ldx #>nbox_ps_wait_lock
    ldy #4
    jmp nbox_print_msg
@pipe_write:
    lda #<nbox_ps_wait_pipe_write
    ldx #>nbox_ps_wait_pipe_write
    ldy #4
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
; nbox_ps_print_row
; ------------------------------------------------------------
.proc nbox_ps_print_row
    lda nbox_procinfo_buf + NBOX_PROCINFO_PID
    jsr nbox_print_hex_byte
    jsr nbox_print_space
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_PPID
    jsr nbox_print_hex_byte
    jsr nbox_print_space
    jsr nbox_print_space
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_STATE
    jsr nbox_ps_print_state
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_WAIT
    jsr nbox_ps_print_wait
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_SIG
    jsr nbox_print_hex_byte
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
; nbox_ps
;
; Show a compact process table view.  Empty process slots are skipped.
; ------------------------------------------------------------
.proc nbox_ps
    lda #<nbox_msg_ps_header
    ldx #>nbox_msg_ps_header
    ldy #NBOX_MSG_PS_HEADER_LEN
    jsr nbox_print_msg

    stz nbox_ps_pid
@loop:
    lda nbox_ps_pid
    cmp #MAX_PROCS
    bcc @pid_ok
    clc
    rts

@pid_ok:
    sta nbox_procinfo_args + procinfo_args::pid
    SYSCALL nbox_procinfo_args, sys_getprocinfo
    bcc @info_ok
    jmp nbox_print_ps_fail

@info_ok:
    lda nbox_procinfo_buf + NBOX_PROCINFO_STATE
    cmp #PROC_EMPTY
    beq @next

    jsr nbox_ps_print_row

@next:
    inc nbox_ps_pid
    bra @loop
.endproc

; ------------------------------------------------------------
; Command wrapper procedures.
; ------------------------------------------------------------
.proc nbox_cmd_help
    jmp nbox_print_help
.endproc

.proc nbox_cmd_pwd
    jmp nbox_pwd
.endproc

.proc nbox_cmd_cd
    jsr nbox_copy_arg_from_y
    jmp nbox_cd
.endproc

.proc nbox_cmd_ls
    jsr nbox_copy_arg_from_y
    jmp nbox_ls
.endproc

.proc nbox_cmd_cat
    jsr nbox_copy_arg_from_y
    jmp nbox_cat
.endproc

.proc nbox_cmd_rm
    jsr nbox_copy_arg_from_y
    jmp nbox_rm
.endproc

.proc nbox_cmd_mv
    jsr nbox_copy_two_args_from_y
    jmp nbox_mv
.endproc

.proc nbox_cmd_mkdir
    jsr nbox_copy_arg_from_y
    jmp nbox_mkdir
.endproc

.proc nbox_cmd_rmdir
    jsr nbox_copy_arg_from_y
    jmp nbox_rmdir
.endproc

.proc nbox_cmd_cp
    jsr nbox_copy_two_args_from_y
    jmp nbox_cp
.endproc

.proc nbox_cmd_ps
    jmp nbox_ps
.endproc

; ------------------------------------------------------------
; nbox_dispatch_line
; ------------------------------------------------------------
.proc nbox_dispatch_line
    ldy #0
@skip:
    lda nbox_line_buf,y
    bne @not_empty
    jmp @done
@not_empty:
    cmp #' '
    beq @skip_next
    cmp #9
    beq @skip_next
    bra @cmd
@skip_next:
    iny
    bra @skip

@cmd:
    jsr nbox_copy_command_token
    bcc @lookup
    jmp nbox_print_unknown

@lookup:
    stz nbox_cmd_idx
    stz nbox_name_offset

@table_loop:
    ldx nbox_name_offset
    lda nbox_cmd_names,x
    cmp #$FF
    beq @unknown

    jsr nbox_command_matches_at_x
    bcc @found

    clc
    lda nbox_name_offset
    adc #NBOX_CMD_NAME_SLOT
    sta nbox_name_offset
    inc nbox_cmd_idx
    bra @table_loop

@found:
    lda nbox_cmd_idx
    asl
    tax
    lda nbox_cmd_handlers,x
    sta nbox_jmpvec
    inx
    lda nbox_cmd_handlers,x
    sta nbox_jmpvec+1

    ldy nbox_line_idx
    jmp (nbox_jmpvec)

@unknown:
    jmp nbox_print_unknown

@done:
    clc
    rts
.endproc

; ------------------------------------------------------------
; Command tables
;
; Fixed-width names avoid zero-page indirect addressing and keep the command
; matcher linker-friendly when nbox.asm is assembled as a separate module.
; Each slot is NBOX_CMD_NAME_SLOT bytes and is zero-padded.
; ------------------------------------------------------------
nbox_cmd_names:
    .byte "HELP", 0, 0
    .byte "PWD", 0, 0, 0
    .byte "CD", 0, 0, 0, 0
    .byte "LS", 0, 0, 0, 0
    .byte "CAT", 0, 0, 0
    .byte "RM", 0, 0, 0, 0
    .byte "MV", 0, 0, 0, 0
    .byte "MKDIR", 0
    .byte "RMDIR", 0
    .byte "CP", 0, 0, 0, 0
    .byte "PS", 0, 0, 0, 0
    .byte $FF, $FF, $FF, $FF, $FF, $FF

nbox_cmd_handlers:
    .word nbox_cmd_help
    .word nbox_cmd_pwd
    .word nbox_cmd_cd
    .word nbox_cmd_ls
    .word nbox_cmd_cat
    .word nbox_cmd_rm
    .word nbox_cmd_mv
    .word nbox_cmd_mkdir
    .word nbox_cmd_rmdir
    .word nbox_cmd_cp
    .word nbox_cmd_ps
