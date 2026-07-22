; ============================================================
; task5.asm
; NEOX - RP filesystem V31-V37 regression test
;
; Purpose:
;   Exercises SYS_SAVE_MEMORY_TO_FILE / SYS_LOAD_FILE_TO_MEMORY, the
;   V32 SYS_OPEN modes, V33 SYS_SEEK / SYS_TELL, and V34 SYS_DELETE /
;   SYS_RENAME and V35 SYS_OPENDIR / SYS_READDIR / SYS_CLOSEDIR and V37 SYS_MKDIR / SYS_RMDIR through the normal user syscall path.
;
; V33 scenario:
;   - create V33TEST.TXT as ABCDE
;   - tell start position = 0
;   - seek EOF, append !, verify ABCDE!
;   - seek END -2, overwrite E with Q, verify ABCDQ!
;   - seek SET 1, then seek CUR +2, overwrite D with R, verify ABCRQ!
;
; V34 scenario:
;   - create V34TEST.TXT as ABCDE
;   - rename V34TEST.TXT to V34REN.TXT
;   - verify renamed file content
;   - delete V34REN.TXT
;   - verify deleted file no longer opens
;
; V35 scenario:
;   - opendir root twice
;   - readdir both handles
;   - verify both independent scans return the same first entry
;   - closedir both handles
;
; V37 scenario:
;   - cleanup stale V37DIR/A.TXT and V37DIR
;   - mkdir V37DIR
;   - chdir V37DIR
;   - create A.TXT through relative cwd
;   - chdir 0:/
;   - verify V37DIR/A.TXT
;   - delete V37DIR/A.TXT
;   - rmdir V37DIR
;   - verify opendir V37DIR fails
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task5_entry
.export user_task5_disabled_entry

T5_DEVICE          = 0
T5_BULK_MAX        = 64
T5_TEXT_LEN        = 18
T5_READ_MAX        = 16
T5_FD_NONE         = $FF
T5_DIRENT_SIZE      = DIR_ENTRY_SIZE

.segment "USER_TEXT"

; ------------------------------------------------------------
; user_task5_disabled_entry
;
; Silent boot-table placeholder used when the regression test body
; must remain linked into the image but must not auto-run at boot.
; ------------------------------------------------------------

.proc user_task5_disabled_entry
    lda #0
    jmp sys_exit
.endproc

.segment "USER_DATA"

t5_bulk_path:
    .byte "BULKTEST.TXT", 0

t5_v32_path:
    .byte "V32TEST.TXT", 0

t5_v32_new_path:
    .byte "V32NEW.TXT", 0

t5_v33_path:
    .byte "V33TEST.TXT", 0

t5_v34_path:
    .byte "V34TEST.TXT", 0

t5_v34_renamed_path:
    .byte "V34REN.TXT", 0

t5_root_path:
    .byte "/", 0

t5_drive0_root_path:
    .byte "0:/", 0

t5_dot_dir_path:
    .byte ".", 0

t5_dot_bulk_path:
    .byte "./BULKTEST.TXT", 0

t5_v37_dir_path:
    .byte "V37DIR", 0

t5_v37_file_path:
    .byte "V37DIR/A.TXT", 0

t5_v37_rel_file_path:
    .byte "A.TXT", 0

t5_expect_cwd_v37:
    .byte "0:/V37DIR", 0

t5_bulk_text:
    .byte "NEOX V31 BULK TEST"

t5_seed_text:
    .byte "ABCDE"

t5_xy_text:
    .byte "XY"

t5_z_text:
    .byte "Z"

t5_new_text:
    .byte "NEW"

t5_bang_text:
    .byte "!"

t5_q_text:
    .byte "Q"

t5_r_text:
    .byte "R"

t5_expect_xycde:
    .byte "XYCDE"

t5_expect_xzcde:
    .byte "XZCDE"

t5_expect_new:
    .byte "NEW"

t5_expect_abcde:
    .byte "ABCDE"

t5_expect_abcde_bang:
    .byte "ABCDE!"

t5_expect_abcdq_bang:
    .byte "ABCDQ!"

t5_expect_abcrq_bang:
    .byte "ABCRQ!"

t5_load_buf:
    .res T5_BULK_MAX

t5_read_buf:
    .res T5_READ_MAX

t5_file_fd:
    .byte T5_FD_NONE

t5_dir_fd1:
    .byte T5_FD_NONE

t5_dir_fd2:
    .byte T5_FD_NONE

t5_cwd_buf:
    .res NEOX_CWD_MAX

t5_expected_pos_lo:
    .byte 0

t5_expected_pos_hi:
    .byte 0

t5_msg_start:
    .byte "T5 V37 START", 13

t5_msg_bulk_fail:
    .byte "T5 BULK FAIL", 13

t5_msg_bulk_ok:
    .byte "T5 BULK OK", 13

t5_msg_trunc_fail:
    .byte "T5 TRUNC FAIL", 13

t5_msg_wexist_fail:
    .byte "T5 WEXIST FAIL", 13

t5_msg_rwexist_fail:
    .byte "T5 RWEXIST FAIL", 13

t5_msg_rwcreate_fail:
    .byte "T5 RWCREATE FAIL", 13

t5_msg_verify_fail:
    .byte "T5 VERIFY FAIL", 13

t5_msg_seek_fail:
    .byte "T5 SEEK FAIL", 13

t5_msg_tell_fail:
    .byte "T5 TELL FAIL", 13

t5_msg_v33_verify_fail:
    .byte "T5 V33 VERIFY FAIL", 13

t5_msg_delete_fail:
    .byte "T5 DELETE FAIL", 13

t5_msg_rename_fail:
    .byte "T5 RENAME FAIL", 13

t5_msg_v34_verify_fail:
    .byte "T5 V34 VERIFY FAIL", 13

t5_msg_opendir_fail:
    .byte "T5 OPENDIR FAIL", 13

t5_msg_readdir_fail:
    .byte "T5 READDIR FAIL", 13

t5_msg_closedir_fail:
    .byte "T5 CLOSEDIR FAIL", 13

t5_msg_v35_verify_fail:
    .byte "T5 V35 VERIFY FAIL", 13

t5_msg_chdir_fail:
    .byte "T5 CHDIR FAIL", 13

t5_msg_getcwd_fail:
    .byte "T5 GETCWD FAIL", 13

t5_msg_v36_verify_fail:
    .byte "T5 V36 VERIFY FAIL", 13

t5_msg_mkdir_fail:
    .byte "T5 MKDIR FAIL", 13

t5_msg_rmdir_fail:
    .byte "T5 RMDIR FAIL", 13

t5_msg_v37_verify_fail:
    .byte "T5 V37 VERIFY FAIL", 13

t5_msg_v32_ok:
    .byte "T5 V32 OK", 13

t5_msg_v33_ok:
    .byte "T5 V33 OK", 13

t5_msg_v34_ok:
    .byte "T5 V34 OK", 13

t5_msg_v35_ok:
    .byte "T5 V35 OK", 13

t5_msg_v36_ok:
    .byte "T5 V36 OK", 13

t5_msg_v37_ok:
    .byte "T5 V37 OK", 13

t5_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t5_file_rw_args:
    .byte T5_FD_NONE
    .byte 0
    .word 0
    .word 0

t5_open_args:
    .word t5_v32_path
    .word 64
    .byte OPEN_READ
    .byte T5_DEVICE

t5_seek_args:
    .byte T5_FD_NONE
    .byte SEEK_SET
    .word 0
    .word 0
    .word 0
    .word 0

t5_tell_args:
    .byte T5_FD_NONE
    .byte 0
    .word 0
    .word 0

t5_delete_args:
    .word t5_v34_path
    .word 64
    .byte T5_DEVICE
    .byte FS_PATH_FLAGS_NONE

t5_rename_args:
    .word t5_v34_path
    .word t5_v34_renamed_path
    .word 64
    .byte T5_DEVICE
    .byte FS_PATH_FLAGS_NONE


t5_dirent1:
    .res T5_DIRENT_SIZE

t5_dirent2:
    .res T5_DIRENT_SIZE

t5_opendir_args:
    .word t5_root_path
    .word 64
    .byte T5_DEVICE
    .byte FS_PATH_FLAGS_NONE

t5_readdir_args:
    .byte T5_FD_NONE
    .byte 0
    .word t5_dirent1
    .word T5_DIRENT_SIZE

t5_closedir_args:
    .byte T5_FD_NONE
    .byte 0

t5_chdir_args:
    .word t5_drive0_root_path
    .word 64
    .byte T5_DEVICE
    .byte NEOX_PATH_FLAGS_NONE

t5_getcwd_args:
    .word t5_cwd_buf
    .word NEOX_CWD_MAX
    .word 0
    .byte NEOX_PATH_FLAGS_NONE
    .byte 0

t5_mkdir_args:
    .word t5_v37_dir_path
    .word 64
    .byte T5_DEVICE
    .byte NEOX_PATH_FLAGS_NONE

t5_rmdir_args:
    .word t5_v37_dir_path
    .word 64
    .byte T5_DEVICE
    .byte NEOX_PATH_FLAGS_NONE

t5_save_args:
    .word t5_bulk_path
    .word t5_bulk_text
    .word T5_TEXT_LEN
    .byte T5_DEVICE
    .byte FS_BULK_FLAGS_NONE

t5_load_args:
    .word t5_bulk_path
    .word t5_load_buf
    .word T5_BULK_MAX
    .byte T5_DEVICE
    .byte FS_BULK_FLAGS_NONE

.segment "USER_TEXT"

; ------------------------------------------------------------
; t5_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = byte length including CR when present
; ------------------------------------------------------------

.proc t5_print_msg
    sta t5_stdout_args + rw_args::buf_ptr
    stx t5_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t5_stdout_args + rw_args::len
    stz t5_stdout_args + rw_args::len + 1

    SYSCALL t5_stdout_args, sys_write
    rts
.endproc

.proc t5_print_start
    lda #<t5_msg_start
    ldx #>t5_msg_start
    ldy #13
    jmp t5_print_msg
.endproc

.proc t5_print_bulk_fail
    lda #<t5_msg_bulk_fail
    ldx #>t5_msg_bulk_fail
    ldy #13
    jmp t5_print_msg
.endproc

.proc t5_print_bulk_ok
    lda #<t5_msg_bulk_ok
    ldx #>t5_msg_bulk_ok
    ldy #11
    jmp t5_print_msg
.endproc

.proc t5_print_trunc_fail
    lda #<t5_msg_trunc_fail
    ldx #>t5_msg_trunc_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_wexist_fail
    lda #<t5_msg_wexist_fail
    ldx #>t5_msg_wexist_fail
    ldy #15
    jmp t5_print_msg
.endproc

.proc t5_print_rwexist_fail
    lda #<t5_msg_rwexist_fail
    ldx #>t5_msg_rwexist_fail
    ldy #16
    jmp t5_print_msg
.endproc

.proc t5_print_rwcreate_fail
    lda #<t5_msg_rwcreate_fail
    ldx #>t5_msg_rwcreate_fail
    ldy #17
    jmp t5_print_msg
.endproc

.proc t5_print_verify_fail
    lda #<t5_msg_verify_fail
    ldx #>t5_msg_verify_fail
    ldy #15
    jmp t5_print_msg
.endproc

.proc t5_print_seek_fail
    lda #<t5_msg_seek_fail
    ldx #>t5_msg_seek_fail
    ldy #13
    jmp t5_print_msg
.endproc

.proc t5_print_tell_fail
    lda #<t5_msg_tell_fail
    ldx #>t5_msg_tell_fail
    ldy #13
    jmp t5_print_msg
.endproc

.proc t5_print_v33_verify_fail
    lda #<t5_msg_v33_verify_fail
    ldx #>t5_msg_v33_verify_fail
    ldy #19
    jmp t5_print_msg
.endproc

.proc t5_print_v32_ok
    lda #<t5_msg_v32_ok
    ldx #>t5_msg_v32_ok
    ldy #10
    jmp t5_print_msg
.endproc

.proc t5_print_v33_ok
    lda #<t5_msg_v33_ok
    ldx #>t5_msg_v33_ok
    ldy #10
    jmp t5_print_msg
.endproc

.proc t5_print_delete_fail
    lda #<t5_msg_delete_fail
    ldx #>t5_msg_delete_fail
    ldy #15
    jmp t5_print_msg
.endproc

.proc t5_print_rename_fail
    lda #<t5_msg_rename_fail
    ldx #>t5_msg_rename_fail
    ldy #15
    jmp t5_print_msg
.endproc

.proc t5_print_v34_verify_fail
    lda #<t5_msg_v34_verify_fail
    ldx #>t5_msg_v34_verify_fail
    ldy #19
    jmp t5_print_msg
.endproc

.proc t5_print_v34_ok
    lda #<t5_msg_v34_ok
    ldx #>t5_msg_v34_ok
    ldy #10
    jmp t5_print_msg
.endproc


.proc t5_print_opendir_fail
    lda #<t5_msg_opendir_fail
    ldx #>t5_msg_opendir_fail
    ldy #16
    jmp t5_print_msg
.endproc

.proc t5_print_readdir_fail
    lda #<t5_msg_readdir_fail
    ldx #>t5_msg_readdir_fail
    ldy #16
    jmp t5_print_msg
.endproc

.proc t5_print_closedir_fail
    lda #<t5_msg_closedir_fail
    ldx #>t5_msg_closedir_fail
    ldy #17
    jmp t5_print_msg
.endproc

.proc t5_print_v35_verify_fail
    lda #<t5_msg_v35_verify_fail
    ldx #>t5_msg_v35_verify_fail
    ldy #19
    jmp t5_print_msg
.endproc

.proc t5_print_v35_ok
    lda #<t5_msg_v35_ok
    ldx #>t5_msg_v35_ok
    ldy #10
    jmp t5_print_msg
.endproc

.proc t5_print_chdir_fail
    lda #<t5_msg_chdir_fail
    ldx #>t5_msg_chdir_fail
    ldy #15
    jmp t5_print_msg
.endproc

.proc t5_print_getcwd_fail
    lda #<t5_msg_getcwd_fail
    ldx #>t5_msg_getcwd_fail
    ldy #16
    jmp t5_print_msg
.endproc

.proc t5_print_v36_verify_fail
    lda #<t5_msg_v36_verify_fail
    ldx #>t5_msg_v36_verify_fail
    ldy #19
    jmp t5_print_msg
.endproc

.proc t5_print_v36_ok
    lda #<t5_msg_v36_ok
    ldx #>t5_msg_v36_ok
    ldy #10
    jmp t5_print_msg
.endproc

.proc t5_print_mkdir_fail
    lda #<t5_msg_mkdir_fail
    ldx #>t5_msg_mkdir_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_rmdir_fail
    lda #<t5_msg_rmdir_fail
    ldx #>t5_msg_rmdir_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_v37_verify_fail
    lda #<t5_msg_v37_verify_fail
    ldx #>t5_msg_v37_verify_fail
    ldy #19
    jmp t5_print_msg
.endproc

.proc t5_print_v37_ok
    lda #<t5_msg_v37_ok
    ldx #>t5_msg_v37_ok
    ldy #10
    jmp t5_print_msg
.endproc

; ------------------------------------------------------------
; t5_close_file
; ------------------------------------------------------------

.proc t5_close_file
    lda t5_file_fd
    cmp #T5_FD_NONE
    beq @done

    pha
    lda #T5_FD_NONE
    sta t5_file_fd
    sta t5_file_rw_args + rw_args::fd
    sta t5_seek_args + seek_args::fd
    sta t5_tell_args + tell_args::fd
    pla
    jsr sys_close

@done:
    rts
.endproc



; ------------------------------------------------------------
; t5_closedir_fd1
; ------------------------------------------------------------

.proc t5_closedir_fd1
    lda t5_dir_fd1
    cmp #T5_FD_NONE
    beq @done

    sta t5_closedir_args + closedir_args::fd
    lda #T5_FD_NONE
    sta t5_dir_fd1
    SYSCALL t5_closedir_args, sys_closedir

@done:
    rts
.endproc

; ------------------------------------------------------------
; t5_closedir_fd2
; ------------------------------------------------------------

.proc t5_closedir_fd2
    lda t5_dir_fd2
    cmp #T5_FD_NONE
    beq @done

    sta t5_closedir_args + closedir_args::fd
    lda #T5_FD_NONE
    sta t5_dir_fd2
    SYSCALL t5_closedir_args, sys_closedir

@done:
    rts
.endproc

; ------------------------------------------------------------
; t5_close_dirs
; ------------------------------------------------------------

.proc t5_close_dirs
    jsr t5_closedir_fd1
    jsr t5_closedir_fd2
    rts
.endproc

; ------------------------------------------------------------
; t5_attach_fd
;
; Input:
;   A = opened fd
; ------------------------------------------------------------

.proc t5_attach_fd
    sta t5_file_fd
    sta t5_file_rw_args + rw_args::fd
    sta t5_seek_args + seek_args::fd
    sta t5_tell_args + tell_args::fd
    rts
.endproc

; ------------------------------------------------------------
; t5_open_path_common
;
; Input:
;   A   = open mode
;   ptr = already stored in t5_open_args::path_ptr
; ------------------------------------------------------------

.proc t5_open_path_common
    sta t5_open_args + open_args::flags
    SYSCALL t5_open_args, sys_open
    bcs @fail

    jsr t5_attach_fd
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_open_v32_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v32_path
    pha
    lda #<t5_v32_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v32_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v32_new_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v32_new_path
    pha
    lda #<t5_v32_new_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v32_new_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v33_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v33_path
    pha
    lda #<t5_v33_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v33_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v34_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v34_path
    pha
    lda #<t5_v34_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v34_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v34_renamed_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v34_renamed_path
    pha
    lda #<t5_v34_renamed_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v34_renamed_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_dot_bulk_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_dot_bulk_path
    pha
    lda #<t5_dot_bulk_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_dot_bulk_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v37_file_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v37_file_path
    pha
    lda #<t5_v37_file_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v37_file_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_open_v37_rel_file_path
;
; Input:
;   A = open mode
; ------------------------------------------------------------

.proc t5_open_v37_rel_file_path
    pha
    lda #<t5_v37_rel_file_path
    sta t5_open_args + open_args::path_ptr
    lda #>t5_v37_rel_file_path
    sta t5_open_args + open_args::path_ptr + 1
    pla
    jmp t5_open_path_common
.endproc

; ------------------------------------------------------------
; t5_file_write
;
; Input:
;   A/X = source pointer
;   Y   = byte length
; ------------------------------------------------------------

.proc t5_file_write
    sta t5_file_rw_args + rw_args::buf_ptr
    stx t5_file_rw_args + rw_args::buf_ptr + 1
    tya
    sta t5_file_rw_args + rw_args::len
    stz t5_file_rw_args + rw_args::len + 1

    SYSCALL t5_file_rw_args, sys_write
    bcs @fail

    cmp t5_file_rw_args + rw_args::len
    bne @fail
    cpx t5_file_rw_args + rw_args::len + 1
    bne @fail

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_file_read
;
; Input:
;   Y = byte length
; ------------------------------------------------------------

.proc t5_file_read
    lda #<t5_read_buf
    sta t5_file_rw_args + rw_args::buf_ptr
    lda #>t5_read_buf
    sta t5_file_rw_args + rw_args::buf_ptr + 1
    tya
    sta t5_file_rw_args + rw_args::len
    stz t5_file_rw_args + rw_args::len + 1

    SYSCALL t5_file_rw_args, sys_read
    rts
.endproc

; ------------------------------------------------------------
; t5_read_v32_path
;
; Input:
;   Y = byte length
; ------------------------------------------------------------

.proc t5_read_v32_path
    phy
    lda #OPEN_READ
    jsr t5_open_v32_path
    bcc :+
    ply
    sec
    rts
:
    ply
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; t5_read_v32_new_path
;
; Input:
;   Y = byte length
; ------------------------------------------------------------

.proc t5_read_v32_new_path
    phy
    lda #OPEN_READ
    jsr t5_open_v32_new_path
    bcc :+
    ply
    sec
    rts
:
    ply
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; t5_read_v33_path
;
; Input:
;   Y = byte length
; ------------------------------------------------------------

.proc t5_read_v33_path
    phy
    lda #OPEN_READ
    jsr t5_open_v33_path
    bcc :+
    ply
    sec
    rts
:
    ply
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; t5_read_v34_renamed_path
;
; Input:
;   Y = byte length
; ------------------------------------------------------------

.proc t5_read_v34_renamed_path
    phy
    lda #OPEN_READ
    jsr t5_open_v34_renamed_path
    bcc :+
    ply
    sec
    rts
:
    ply
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; t5_check_pos
;
; Input:
;   A/X = low word returned by seek/tell syscall
;   t5_expected_pos_lo/hi = expected low word
; ------------------------------------------------------------

.proc t5_check_pos
    cmp t5_expected_pos_lo
    bne @fail
    cpx t5_expected_pos_hi
    bne @fail

    lda t5_seek_args + seek_args::result_lo
    cmp t5_expected_pos_lo
    bne @fail
    lda t5_seek_args + seek_args::result_lo + 1
    cmp t5_expected_pos_hi
    bne @fail
    lda t5_seek_args + seek_args::result_hi
    bne @fail
    lda t5_seek_args + seek_args::result_hi + 1
    bne @fail

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_check_tell_pos
;
; Input:
;   A/X = low word returned by tell syscall
;   t5_expected_pos_lo/hi = expected low word
; ------------------------------------------------------------

.proc t5_check_tell_pos
    cmp t5_expected_pos_lo
    bne @fail
    cpx t5_expected_pos_hi
    bne @fail

    lda t5_tell_args + tell_args::result_lo
    cmp t5_expected_pos_lo
    bne @fail
    lda t5_tell_args + tell_args::result_lo + 1
    cmp t5_expected_pos_hi
    bne @fail
    lda t5_tell_args + tell_args::result_hi
    bne @fail
    lda t5_tell_args + tell_args::result_hi + 1
    bne @fail

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_seek_file
;
; Input:
;   t5_seek_args populated
;   t5_expected_pos_lo/hi populated
; ------------------------------------------------------------

.proc t5_seek_file
    lda #0
    sta t5_seek_args + seek_args::result_lo
    sta t5_seek_args + seek_args::result_lo + 1
    sta t5_seek_args + seek_args::result_hi
    sta t5_seek_args + seek_args::result_hi + 1

    SYSCALL t5_seek_args, sys_seek
    bcs @fail

    jsr t5_check_pos
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_tell_file
;
; Input:
;   t5_expected_pos_lo/hi populated
; ------------------------------------------------------------

.proc t5_tell_file
    lda #0
    sta t5_tell_args + tell_args::result_lo
    sta t5_tell_args + tell_args::result_lo + 1
    sta t5_tell_args + tell_args::result_hi
    sta t5_tell_args + tell_args::result_hi + 1

    SYSCALL t5_tell_args, sys_tell
    bcs @fail

    jsr t5_check_tell_pos
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_prepare_seek
;
; Input:
;   A = whence
; ------------------------------------------------------------

.proc t5_prepare_seek
    sta t5_seek_args + seek_args::whence
    stz t5_seek_args + seek_args::offset_lo
    stz t5_seek_args + seek_args::offset_lo + 1
    stz t5_seek_args + seek_args::offset_hi
    stz t5_seek_args + seek_args::offset_hi + 1
    stz t5_expected_pos_lo
    stz t5_expected_pos_hi
    rts
.endproc

; ------------------------------------------------------------
; t5_seek_end_0_expect5
; ------------------------------------------------------------

.proc t5_seek_end_0_expect5
    lda #SEEK_END
    jsr t5_prepare_seek
    lda #5
    sta t5_expected_pos_lo
    jmp t5_seek_file
.endproc

; ------------------------------------------------------------
; t5_seek_end_minus2_expect4
; ------------------------------------------------------------

.proc t5_seek_end_minus2_expect4
    lda #SEEK_END
    jsr t5_prepare_seek
    lda #$FE
    sta t5_seek_args + seek_args::offset_lo
    lda #$FF
    sta t5_seek_args + seek_args::offset_lo + 1
    sta t5_seek_args + seek_args::offset_hi
    sta t5_seek_args + seek_args::offset_hi + 1
    lda #4
    sta t5_expected_pos_lo
    jmp t5_seek_file
.endproc

; ------------------------------------------------------------
; t5_seek_set_1_expect1
; ------------------------------------------------------------

.proc t5_seek_set_1_expect1
    lda #SEEK_SET
    jsr t5_prepare_seek
    lda #1
    sta t5_seek_args + seek_args::offset_lo
    sta t5_expected_pos_lo
    jmp t5_seek_file
.endproc

; ------------------------------------------------------------
; t5_seek_cur_2_expect3
; ------------------------------------------------------------

.proc t5_seek_cur_2_expect3
    lda #SEEK_CUR
    jsr t5_prepare_seek
    lda #2
    sta t5_seek_args + seek_args::offset_lo
    lda #3
    sta t5_expected_pos_lo
    jmp t5_seek_file
.endproc

; ------------------------------------------------------------
; t5_tell_expect0
; ------------------------------------------------------------

.proc t5_tell_expect0
    stz t5_expected_pos_lo
    stz t5_expected_pos_hi
    jmp t5_tell_file
.endproc

; ------------------------------------------------------------
; t5_verify_xycde
; ------------------------------------------------------------

.proc t5_verify_xycde
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_xycde,y
    bne @fail
    iny
    cpy #5
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_xzcde
; ------------------------------------------------------------

.proc t5_verify_xzcde
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_xzcde,y
    bne @fail
    iny
    cpy #5
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_new
; ------------------------------------------------------------

.proc t5_verify_new
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_new,y
    bne @fail
    iny
    cpy #3
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_abcde
; ------------------------------------------------------------

.proc t5_verify_abcde
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_abcde,y
    bne @fail
    iny
    cpy #5
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_abcde_bang
; ------------------------------------------------------------

.proc t5_verify_abcde_bang
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_abcde_bang,y
    bne @fail
    iny
    cpy #6
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_abcdq_bang
; ------------------------------------------------------------

.proc t5_verify_abcdq_bang
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_abcdq_bang,y
    bne @fail
    iny
    cpy #6
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_abcrq_bang
; ------------------------------------------------------------

.proc t5_verify_abcrq_bang
    ldy #0
@loop:
    lda t5_read_buf,y
    cmp t5_expect_abcrq_bang,y
    bne @fail
    iny
    cpy #6
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_run_bulk_v31
; ------------------------------------------------------------

.proc t5_run_bulk_v31
    SYSCALL t5_save_args, sys_save_memory_to_file
    bcs @fail
    cmp #T5_TEXT_LEN
    bne @fail
    cpx #0
    bne @fail

    SYSCALL t5_load_args, sys_load_file_to_memory
    bcs @fail
    cmp #T5_TEXT_LEN
    bne @fail
    cpx #0
    bne @fail

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v32_open_modes
; ------------------------------------------------------------

.proc t5_run_v32_open_modes
    ; OPEN_WRITE_TRUNC: create/truncate V32TEST.TXT and seed ABCDE.
    lda #OPEN_WRITE_TRUNC
    jsr t5_open_v32_path
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:
    lda #<t5_seed_text
    ldx #>t5_seed_text
    ldy #5
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:

    ; OPEN_WRITE_EXISTING: overwrite first two bytes, preserving tail.
    lda #OPEN_WRITE_EXISTING
    jsr t5_open_v32_path
    bcc :+
    jsr t5_print_wexist_fail
    sec
    rts
:
    lda #<t5_xy_text
    ldx #>t5_xy_text
    ldy #2
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_wexist_fail
    sec
    rts
:

    ldy #5
    jsr t5_read_v32_path
    bcc :+
    jsr t5_print_verify_fail
    sec
    rts
:
    cmp #5
    bne @verify_fail_xycde
    cpx #0
    bne @verify_fail_xycde
    jsr t5_verify_xycde
    bcc :+
@verify_fail_xycde:
    jsr t5_print_verify_fail
    sec
    rts
:

    ; OPEN_RW_EXISTING: read one byte, then write at the resulting offset.
    lda #OPEN_RW_EXISTING
    jsr t5_open_v32_path
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:
    ldy #1
    jsr t5_file_read
    bcc :+
    jsr t5_close_file
    jsr t5_print_rwexist_fail
    sec
    rts
:
    cmp #1
    bne @rwexist_read_count_fail
    cpx #0
    beq :+
@rwexist_read_count_fail:
    jsr t5_close_file
    jsr t5_print_rwexist_fail
    sec
    rts
:
    lda #<t5_z_text
    ldx #>t5_z_text
    ldy #1
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:

    ldy #5
    jsr t5_read_v32_path
    bcc :+
    jsr t5_print_verify_fail
    sec
    rts
:
    cmp #5
    bne @verify_fail_xzcde
    cpx #0
    bne @verify_fail_xzcde
    jsr t5_verify_xzcde
    bcc :+
@verify_fail_xzcde:
    jsr t5_print_verify_fail
    sec
    rts
:

    ; OPEN_RW_CREATE: create-if-missing/open-existing and verify first 3 bytes.
    lda #OPEN_RW_CREATE
    jsr t5_open_v32_new_path
    bcc :+
    jsr t5_print_rwcreate_fail
    sec
    rts
:
    lda #<t5_new_text
    ldx #>t5_new_text
    ldy #3
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_rwcreate_fail
    sec
    rts
:

    ldy #3
    jsr t5_read_v32_new_path
    bcc :+
    jsr t5_print_verify_fail
    sec
    rts
:
    cmp #3
    bne @verify_fail_new
    cpx #0
    bne @verify_fail_new
    jsr t5_verify_new
    bcc :+
@verify_fail_new:
    jsr t5_print_verify_fail
    sec
    rts
:

    clc
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v33_seek_tell
; ------------------------------------------------------------

.proc t5_run_v33_seek_tell
    ; Seed V33TEST.TXT with ABCDE.
    lda #OPEN_WRITE_TRUNC
    jsr t5_open_v33_path
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:
    lda #<t5_seed_text
    ldx #>t5_seed_text
    ldy #5
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:

    ; Open read/write and prove tell at BOF, then append via SEEK_END.
    lda #OPEN_RW_EXISTING
    jsr t5_open_v33_path
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:
    jsr t5_tell_expect0
    bcc :+
    jsr t5_close_file
    jsr t5_print_tell_fail
    sec
    rts
:
    jsr t5_seek_end_0_expect5
    bcc :+
    jsr t5_close_file
    jsr t5_print_seek_fail
    sec
    rts
:
    lda #<t5_bang_text
    ldx #>t5_bang_text
    ldy #1
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:

    ldy #6
    jsr t5_read_v33_path
    bcc :+
    jsr t5_print_v33_verify_fail
    sec
    rts
:
    cmp #6
    bne @verify_fail_abcde_bang
    cpx #0
    bne @verify_fail_abcde_bang
    jsr t5_verify_abcde_bang
    bcc :+
@verify_fail_abcde_bang:
    jsr t5_print_v33_verify_fail
    sec
    rts
:

    ; SEEK_END with signed -2: overwrite E at position 4 with Q.
    lda #OPEN_RW_EXISTING
    jsr t5_open_v33_path
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:
    jsr t5_seek_end_minus2_expect4
    bcc :+
    jsr t5_close_file
    jsr t5_print_seek_fail
    sec
    rts
:
    lda #<t5_q_text
    ldx #>t5_q_text
    ldy #1
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:

    ldy #6
    jsr t5_read_v33_path
    bcc :+
    jsr t5_print_v33_verify_fail
    sec
    rts
:
    cmp #6
    bne @verify_fail_abcdq_bang
    cpx #0
    bne @verify_fail_abcdq_bang
    jsr t5_verify_abcdq_bang
    bcc :+
@verify_fail_abcdq_bang:
    jsr t5_print_v33_verify_fail
    sec
    rts
:

    ; SEEK_SET 1 followed by SEEK_CUR +2: final position 3, overwrite D with R.
    lda #OPEN_RW_EXISTING
    jsr t5_open_v33_path
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:
    jsr t5_seek_set_1_expect1
    bcc :+
    jsr t5_close_file
    jsr t5_print_seek_fail
    sec
    rts
:
    jsr t5_seek_cur_2_expect3
    bcc :+
    jsr t5_close_file
    jsr t5_print_seek_fail
    sec
    rts
:
    lda #<t5_r_text
    ldx #>t5_r_text
    ldy #1
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_rwexist_fail
    sec
    rts
:

    ldy #6
    jsr t5_read_v33_path
    bcc :+
    jsr t5_print_v33_verify_fail
    sec
    rts
:
    cmp #6
    bne @verify_fail_abcrq_bang
    cpx #0
    bne @verify_fail_abcrq_bang
    jsr t5_verify_abcrq_bang
    bcc :+
@verify_fail_abcrq_bang:
    jsr t5_print_v33_verify_fail
    sec
    rts
:

    clc
    rts
.endproc


; ------------------------------------------------------------
; t5_delete_v34_path
; ------------------------------------------------------------

.proc t5_delete_v34_path
    lda #<t5_v34_path
    sta t5_delete_args + delete_args::path_ptr
    lda #>t5_v34_path
    sta t5_delete_args + delete_args::path_ptr + 1
    SYSCALL t5_delete_args, sys_delete
    rts
.endproc

; ------------------------------------------------------------
; t5_delete_v34_renamed_path
; ------------------------------------------------------------

.proc t5_delete_v34_renamed_path
    lda #<t5_v34_renamed_path
    sta t5_delete_args + delete_args::path_ptr
    lda #>t5_v34_renamed_path
    sta t5_delete_args + delete_args::path_ptr + 1
    SYSCALL t5_delete_args, sys_delete
    rts
.endproc

; ------------------------------------------------------------
; t5_rename_v34_path
; ------------------------------------------------------------

.proc t5_rename_v34_path
    lda #<t5_v34_path
    sta t5_rename_args + rename_args::old_path_ptr
    lda #>t5_v34_path
    sta t5_rename_args + rename_args::old_path_ptr + 1
    lda #<t5_v34_renamed_path
    sta t5_rename_args + rename_args::new_path_ptr
    lda #>t5_v34_renamed_path
    sta t5_rename_args + rename_args::new_path_ptr + 1
    SYSCALL t5_rename_args, sys_rename
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v34_delete_rename
; ------------------------------------------------------------

.proc t5_run_v34_delete_rename
    ; Cleanup from prior runs. Missing-file failures are intentionally ignored.
    jsr t5_delete_v34_path
    jsr t5_delete_v34_renamed_path

    ; Create V34TEST.TXT with ABCDE.
    lda #OPEN_WRITE_TRUNC
    jsr t5_open_v34_path
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:
    lda #<t5_seed_text
    ldx #>t5_seed_text
    ldy #5
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:

    ; Rename V34TEST.TXT to V34REN.TXT.
    jsr t5_rename_v34_path
    bcc :+
    jsr t5_print_rename_fail
    sec
    rts
:

    ; Old path should no longer open.
    lda #OPEN_READ
    jsr t5_open_v34_path
    bcs :+
    jsr t5_close_file
    jsr t5_print_rename_fail
    sec
    rts
:

    ; Renamed path should contain ABCDE.
    ldy #5
    jsr t5_read_v34_renamed_path
    bcc :+
    jsr t5_print_v34_verify_fail
    sec
    rts
:
    cmp #5
    bne @verify_fail_abcde
    cpx #0
    bne @verify_fail_abcde
    jsr t5_verify_abcde
    bcc :+
@verify_fail_abcde:
    jsr t5_print_v34_verify_fail
    sec
    rts
:

    ; Delete renamed file and prove it no longer opens.
    jsr t5_delete_v34_renamed_path
    bcc :+
    jsr t5_print_delete_fail
    sec
    rts
:

    lda #OPEN_READ
    jsr t5_open_v34_renamed_path
    bcs :+
    jsr t5_close_file
    jsr t5_print_delete_fail
    sec
    rts
:
    clc
    rts
.endproc


; ------------------------------------------------------------
; t5_opendir_root_fd1
; ------------------------------------------------------------

.proc t5_opendir_root_fd1
    lda #<t5_root_path
    sta t5_opendir_args + opendir_args::path_ptr
    lda #>t5_root_path
    sta t5_opendir_args + opendir_args::path_ptr + 1
    SYSCALL t5_opendir_args, sys_opendir
    bcs @fail

    sta t5_dir_fd1
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_opendir_root_fd2
; ------------------------------------------------------------

.proc t5_opendir_root_fd2
    lda #<t5_root_path
    sta t5_opendir_args + opendir_args::path_ptr
    lda #>t5_root_path
    sta t5_opendir_args + opendir_args::path_ptr + 1
    SYSCALL t5_opendir_args, sys_opendir
    bcs @fail

    sta t5_dir_fd2
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_readdir_fd1
; ------------------------------------------------------------

.proc t5_readdir_fd1
    lda t5_dir_fd1
    sta t5_readdir_args + readdir_args::fd
    lda #<t5_dirent1
    sta t5_readdir_args + readdir_args::entry_ptr
    lda #>t5_dirent1
    sta t5_readdir_args + readdir_args::entry_ptr + 1
    SYSCALL t5_readdir_args, sys_readdir
    rts
.endproc

; ------------------------------------------------------------
; t5_readdir_fd2
; ------------------------------------------------------------

.proc t5_readdir_fd2
    lda t5_dir_fd2
    sta t5_readdir_args + readdir_args::fd
    lda #<t5_dirent2
    sta t5_readdir_args + readdir_args::entry_ptr
    lda #>t5_dirent2
    sta t5_readdir_args + readdir_args::entry_ptr + 1
    SYSCALL t5_readdir_args, sys_readdir
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_dirents_same_first_name
; ------------------------------------------------------------

.proc t5_verify_dirents_same_first_name
    lda t5_dirent1
    beq @fail
    lda t5_dirent2
    beq @fail

    ldy #0
@loop:
    lda t5_dirent1,y
    cmp t5_dirent2,y
    bne @fail
    iny
    cpy #DIR_ENTRY_NAME_SIZE
    bne @loop

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v35_directory_control
; ------------------------------------------------------------

.proc t5_run_v35_directory_control
    jsr t5_close_dirs

    ; Open two independent scans of root.  Each user-visible handle is a
    ; normal NEOX fd; the RP DIR handles remain kernel-private.
    jsr t5_opendir_root_fd1
    bcc :+
    jsr t5_print_opendir_fail
    sec
    rts
:
    jsr t5_opendir_root_fd2
    bcc :+
    jsr t5_close_dirs
    jsr t5_print_opendir_fail
    sec
    rts
:

    ; Read one entry from each scan.  Root is expected to be non-empty
    ; because earlier V31-V34 tests have created files in it.
    jsr t5_readdir_fd1
    bcc :+
    jsr t5_close_dirs
    jsr t5_print_readdir_fail
    sec
    rts
:
    cmp #1
    bne @readdir_fail
    cpx #0
    bne @readdir_fail

    jsr t5_readdir_fd2
    bcc :+
@readdir_fail:
    jsr t5_close_dirs
    jsr t5_print_readdir_fail
    sec
    rts
:
    cmp #1
    bne @readdir_fail2
    cpx #0
    beq :+
@readdir_fail2:
    jsr t5_close_dirs
    jsr t5_print_readdir_fail
    sec
    rts
:

    ; Two independent opendir calls over the same directory should start
    ; at the same first entry.
    jsr t5_verify_dirents_same_first_name
    bcc :+
    jsr t5_close_dirs
    jsr t5_print_v35_verify_fail
    sec
    rts
:

    jsr t5_closedir_fd1
    bcc :+
    jsr t5_close_dirs
    jsr t5_print_closedir_fail
    sec
    rts
:
    jsr t5_closedir_fd2
    bcc :+
    jsr t5_print_closedir_fail
    sec
    rts
:

    clc
    rts
.endproc


; ------------------------------------------------------------
; t5_verify_getcwd_root0
; ------------------------------------------------------------

.proc t5_verify_getcwd_root0
    lda t5_getcwd_args + getcwd_args::result_len
    cmp #3
    bne @fail
    lda t5_getcwd_args + getcwd_args::result_len + 1
    bne @fail
    lda t5_cwd_buf
    cmp #'0'
    bne @fail
    lda t5_cwd_buf+1
    cmp #':'
    bne @fail
    lda t5_cwd_buf+2
    cmp #'/'
    bne @fail
    lda t5_cwd_buf+3
    bne @fail
    clc
    rts
@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_opendir_dot_fd1
; ------------------------------------------------------------

.proc t5_opendir_dot_fd1
    lda #<t5_dot_dir_path
    sta t5_opendir_args + opendir_args::path_ptr
    lda #>t5_dot_dir_path
    sta t5_opendir_args + opendir_args::path_ptr + 1
    SYSCALL t5_opendir_args, sys_opendir
    bcs @fail
    sta t5_dir_fd1
    clc
    rts
@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v36_current_dir
; ------------------------------------------------------------

.proc t5_run_v36_current_dir
    ; chdir("0:/") establishes an explicit drive-qualified cwd root.
    lda #<t5_drive0_root_path
    sta t5_chdir_args + chdir_args::path_ptr
    lda #>t5_drive0_root_path
    sta t5_chdir_args + chdir_args::path_ptr + 1
    SYSCALL t5_chdir_args, sys_chdir
    bcc :+
    jsr t5_print_chdir_fail
    sec
    rts
:
    ; getcwd must return "0:/".
    SYSCALL t5_getcwd_args, sys_getcwd
    bcc :+
    jsr t5_print_getcwd_fail
    sec
    rts
:
    jsr t5_verify_getcwd_root0
    bcc :+
    jsr t5_print_getcwd_fail
    sec
    rts
:
    ; opendir(".") must resolve to the current directory.
    jsr t5_close_dirs
    jsr t5_opendir_dot_fd1
    bcc :+
    jsr t5_print_opendir_fail
    sec
    rts
:
    jsr t5_readdir_fd1
    bcc :+
    jsr t5_close_dirs
    jsr t5_print_readdir_fail
    sec
    rts
:
    cmp #1
    bne @readdir_bad
    cpx #0
    beq :+
@readdir_bad:
    jsr t5_close_dirs
    jsr t5_print_readdir_fail
    sec
    rts
:
    jsr t5_closedir_fd1
    bcc :+
    jsr t5_print_closedir_fail
    sec
    rts
:
    ; open("./BULKTEST.TXT") must resolve against cwd and read the V31 file.
    lda #OPEN_READ
    jsr t5_open_dot_bulk_path
    bcc :+
    jsr t5_print_v36_verify_fail
    sec
    rts
:
    ldy #T5_TEXT_LEN
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    bcc :+
    jsr t5_print_v36_verify_fail
    sec
    rts
:
    cmp #T5_TEXT_LEN
    bne @read_bad
    cpx #0
    beq :+
@read_bad:
    jsr t5_print_v36_verify_fail
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; t5_chdir_drive0_root
; ------------------------------------------------------------

.proc t5_chdir_drive0_root
    lda #<t5_drive0_root_path
    sta t5_chdir_args + chdir_args::path_ptr
    lda #>t5_drive0_root_path
    sta t5_chdir_args + chdir_args::path_ptr + 1
    SYSCALL t5_chdir_args, sys_chdir
    rts
.endproc

; ------------------------------------------------------------
; t5_chdir_v37_dir
; ------------------------------------------------------------

.proc t5_chdir_v37_dir
    lda #<t5_v37_dir_path
    sta t5_chdir_args + chdir_args::path_ptr
    lda #>t5_v37_dir_path
    sta t5_chdir_args + chdir_args::path_ptr + 1
    SYSCALL t5_chdir_args, sys_chdir
    rts
.endproc

; ------------------------------------------------------------
; t5_verify_getcwd_v37
; ------------------------------------------------------------

.proc t5_verify_getcwd_v37
    lda t5_getcwd_args + getcwd_args::result_len
    cmp #9
    bne @fail
    lda t5_getcwd_args + getcwd_args::result_len + 1
    bne @fail

    ldy #0
@loop:
    lda t5_cwd_buf,y
    cmp t5_expect_cwd_v37,y
    bne @fail
    beq @check_end
@next:
    iny
    bra @loop
@check_end:
    lda t5_expect_cwd_v37,y
    beq @ok
    bra @next
@ok:
    clc
    rts
@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_delete_v37_file_path
; ------------------------------------------------------------

.proc t5_delete_v37_file_path
    lda #<t5_v37_file_path
    sta t5_delete_args + delete_args::path_ptr
    lda #>t5_v37_file_path
    sta t5_delete_args + delete_args::path_ptr + 1
    SYSCALL t5_delete_args, sys_delete
    rts
.endproc

; ------------------------------------------------------------
; t5_mkdir_v37_dir
; ------------------------------------------------------------

.proc t5_mkdir_v37_dir
    lda #<t5_v37_dir_path
    sta t5_mkdir_args + mkdir_args::path_ptr
    lda #>t5_v37_dir_path
    sta t5_mkdir_args + mkdir_args::path_ptr + 1
    SYSCALL t5_mkdir_args, sys_mkdir
    rts
.endproc

; ------------------------------------------------------------
; t5_rmdir_v37_dir
; ------------------------------------------------------------

.proc t5_rmdir_v37_dir
    lda #<t5_v37_dir_path
    sta t5_rmdir_args + rmdir_args::path_ptr
    lda #>t5_v37_dir_path
    sta t5_rmdir_args + rmdir_args::path_ptr + 1
    SYSCALL t5_rmdir_args, sys_rmdir
    rts
.endproc

; ------------------------------------------------------------
; t5_opendir_v37_dir_fd1
; ------------------------------------------------------------

.proc t5_opendir_v37_dir_fd1
    lda #<t5_v37_dir_path
    sta t5_opendir_args + opendir_args::path_ptr
    lda #>t5_v37_dir_path
    sta t5_opendir_args + opendir_args::path_ptr + 1
    SYSCALL t5_opendir_args, sys_opendir
    bcs @fail
    sta t5_dir_fd1
    clc
    rts
@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_run_v37_mkdir_rmdir
; ------------------------------------------------------------

.proc t5_run_v37_mkdir_rmdir
    ; Start from root.
    jsr t5_chdir_drive0_root
    bcc :+
    jsr t5_print_chdir_fail
    sec
    rts
:

    ; Cleanup from earlier runs. Missing-file/missing-directory failures are ignored.
    jsr t5_delete_v37_file_path
    jsr t5_rmdir_v37_dir

    ; mkdir("V37DIR") from root.
    jsr t5_mkdir_v37_dir
    bcc :+
    jsr t5_print_mkdir_fail
    sec
    rts
:

    ; chdir("V37DIR") and verify getcwd is 0:/V37DIR.
    jsr t5_chdir_v37_dir
    bcc :+
    jsr t5_print_chdir_fail
    sec
    rts
:
    SYSCALL t5_getcwd_args, sys_getcwd
    bcc :+
    jsr t5_print_getcwd_fail
    sec
    rts
:
    jsr t5_verify_getcwd_v37
    bcc :+
    jsr t5_print_getcwd_fail
    sec
    rts
:

    ; Create A.TXT using relative cwd.
    lda #OPEN_WRITE_TRUNC
    jsr t5_open_v37_rel_file_path
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:
    lda #<t5_seed_text
    ldx #>t5_seed_text
    ldy #5
    jsr t5_file_write
    php
    jsr t5_close_file
    plp
    bcc :+
    jsr t5_print_trunc_fail
    sec
    rts
:

    ; Return to root and verify the file through V37DIR/A.TXT.
    jsr t5_chdir_drive0_root
    bcc :+
    jsr t5_print_chdir_fail
    sec
    rts
:
    ldy #5
    phy
    lda #OPEN_READ
    jsr t5_open_v37_file_path
    bcc :+
    ply
    jsr t5_print_v37_verify_fail
    sec
    rts
:
    ply
    jsr t5_file_read
    php
    pha
    phx
    jsr t5_close_file
    plx
    pla
    plp
    bcc :+
    jsr t5_print_v37_verify_fail
    sec
    rts
:
    cmp #5
    bne @verify_fail
    cpx #0
    bne @verify_fail
    jsr t5_verify_abcde
    bcc :+
@verify_fail:
    jsr t5_print_v37_verify_fail
    sec
    rts
:

    ; Delete file, remove directory, and prove directory no longer opens.
    jsr t5_delete_v37_file_path
    bcc :+
    jsr t5_print_delete_fail
    sec
    rts
:
    jsr t5_rmdir_v37_dir
    bcc :+
    jsr t5_print_rmdir_fail
    sec
    rts
:
    jsr t5_opendir_v37_dir_fd1
    bcs :+
    jsr t5_closedir_fd1
    jsr t5_print_v37_verify_fail
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; user_task5_entry
; ------------------------------------------------------------

.proc user_task5_entry
    jsr t5_print_start

    jsr t5_run_bulk_v31
    bcc :+
    jsr t5_print_bulk_fail
    jmp @exit
:
    jsr t5_print_bulk_ok

    jsr t5_run_v32_open_modes
    bcc :+
    jmp @exit
:
    jsr t5_print_v32_ok

    jsr t5_run_v33_seek_tell
    bcc :+
    jmp @exit
:
    jsr t5_print_v33_ok

    jsr t5_run_v34_delete_rename
    bcc :+
    jmp @exit
:
    jsr t5_print_v34_ok

    jsr t5_run_v35_directory_control
    bcc :+
    jmp @exit
:
    jsr t5_print_v35_ok

    jsr t5_run_v36_current_dir
    bcc :+
    jmp @exit
:
    jsr t5_print_v36_ok

    jsr t5_run_v37_mkdir_rmdir
    bcc :+
    jmp @exit
:
    jsr t5_print_v37_ok

@exit:
    jsr t5_close_file
    jsr t5_close_dirs
    jmp sys_exit
.endproc
