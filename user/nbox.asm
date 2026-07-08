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
.include "nbox.inc"

.import nbox_cmd_help
.import nbox_cmd_pwd
.import nbox_cmd_cd
.import nbox_cmd_ls
.import nbox_cmd_cat
.import nbox_cmd_rm
.import nbox_cmd_mv
.import nbox_cmd_mkdir
.import nbox_cmd_rmdir
.import nbox_cmd_cp
.import nbox_cmd_ps
.import nbox_cmd_spawn
.import nbox_cmd_spawnc

.export nbox_line_buf
.export nbox_line_len
.export nbox_dispatch_line

.export nbox_arg_buf
.export nbox_arg2_buf
.export nbox_arg_len
.export nbox_arg2_len
.export nbox_cwd_buf
.export nbox_dir_entry
.export nbox_cat_buf
.export nbox_dir_fd
.export nbox_file_fd
.export nbox_cp_src_fd
.export nbox_cp_dst_fd
.export nbox_src_idx
.export nbox_dst_idx
.export nbox_type_prefix
.export nbox_getcwd_args
.export nbox_chdir_args
.export nbox_opendir_args
.export nbox_readdir_args
.export nbox_closedir_args
.export nbox_open_args
.export nbox_cat_rw_args
.export nbox_cp_src_open_args
.export nbox_cp_dst_open_args
.export nbox_cp_dst_opendir_args
.export nbox_cp_read_args
.export nbox_cp_write_args
.export nbox_delete_args
.export nbox_rename_args
.export nbox_mkdir_args
.export nbox_rmdir_args
.export nbox_procinfo_buf
.export nbox_ps_pid
.export nbox_procinfo_args
.export nbox_stdout_args
.export nbox_msg_ps_header
.export nbox_ps_state_empty
.export nbox_ps_state_new
.export nbox_ps_state_ready
.export nbox_ps_state_running
.export nbox_ps_state_blocked
.export nbox_ps_state_stopped
.export nbox_ps_state_zombie
.export nbox_ps_state_setup
.export nbox_ps_state_unknown
.export nbox_ps_wait_none
.export nbox_ps_wait_console
.export nbox_ps_wait_device
.export nbox_ps_wait_pipe_read
.export nbox_ps_wait_timer
.export nbox_ps_wait_proc
.export nbox_ps_wait_lock
.export nbox_ps_wait_pipe_write
.export nbox_ps_wait_unknown
.export nbox_print_msg
.export nbox_print_cr
.export nbox_print_help
.export nbox_print_unknown
.export nbox_print_arg_fail
.export nbox_print_cd_fail
.export nbox_print_ls_fail
.export nbox_print_readdir_fail
.export nbox_print_cat_fail
.export nbox_print_rm_fail
.export nbox_print_mv_fail
.export nbox_print_mkdir_fail
.export nbox_print_rmdir_fail
.export nbox_print_cp_fail
.export nbox_print_ps_fail
.export nbox_print_space
.export nbox_print_hex_byte
.export nbox_copy_arg_from_y
.export nbox_copy_two_args_from_y
.export nbox_require_arg
.export nbox_require_two_args
.export nbox_default_arg_dot_if_empty
.export nbox_default_arg_root_if_empty
.export nbox_strlen_dirent_name
.export nbox_ls_close_dir

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
    .byte "COMMANDS: HELP PWD CD LS CAT RM MV MKDIR RMDIR CP PS SPAWN SPAWNC", 13
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
nbox_ps_state_setup:
    .byte "SET"
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
; nbox_clear_cmd_buf
; ------------------------------------------------------------
.proc nbox_clear_cmd_buf
    stz nbox_cmd_buf
    stz nbox_cmd_buf+1
    stz nbox_cmd_buf+2
    stz nbox_cmd_buf+3
    stz nbox_cmd_buf+4
    stz nbox_cmd_buf+5
    stz nbox_cmd_buf+6
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
    inx
    lda nbox_cmd_buf+6
    cmp nbox_cmd_names,x
    bne @no

    clc
    rts
@no:
    sec
    rts
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
    .byte "HELP", 0, 0, 0
    .byte "PWD", 0, 0, 0, 0
    .byte "CD", 0, 0, 0, 0, 0
    .byte "LS", 0, 0, 0, 0, 0
    .byte "CAT", 0, 0, 0, 0
    .byte "RM", 0, 0, 0, 0, 0
    .byte "MV", 0, 0, 0, 0, 0
    .byte "MKDIR", 0, 0
    .byte "RMDIR", 0, 0
    .byte "CP", 0, 0, 0, 0, 0
    .byte "PS", 0, 0, 0, 0, 0
    .byte "SPAWN", 0, 0
    .byte "SPAWNC", 0
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF

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
    .word nbox_cmd_spawn
    .word nbox_cmd_spawnc
