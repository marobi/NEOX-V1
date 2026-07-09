; ============================================================
; ls.asm
; NEOX nbox applet: ls
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_ls
.export nbox_ls

.segment "USER_DATA"

nbox_ls_opendir_args:
    .word nbox_arg_buf
    .word NBOX_PATH_MAX
    .byte 0
    .byte NEOX_PATH_FLAGS_NONE

nbox_ls_readdir_args:
    .byte NBOX_DIR_FD_NONE
    .byte 0
    .word nbox_dir_entry
    .word DIR_ENTRY_SIZE

nbox_ls_closedir_args:
    .byte NBOX_DIR_FD_NONE
    .byte 0

nbox_ls_type_prefix:
    .byte "- "

.segment "USER_TEXT"

; ------------------------------------------------------------
nbox_ls_msg_fail:
    .byte "LS FAIL", 13
NBOX_LS_MSG_FAIL_LEN = * - nbox_ls_msg_fail

nbox_ls_msg_readdir_fail:
    .byte "READDIR FAIL", 13
NBOX_LS_MSG_READDIR_FAIL_LEN = * - nbox_ls_msg_readdir_fail

.proc nbox_print_ls_fail
    lda #<nbox_ls_msg_fail
    ldx #>nbox_ls_msg_fail
    ldy #NBOX_LS_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

.proc nbox_print_readdir_fail
    lda #<nbox_ls_msg_readdir_fail
    ldx #>nbox_ls_msg_readdir_fail
    ldy #NBOX_LS_MSG_READDIR_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
; nbox_ls_close_dir
;
; Close the currently-open directory handle. The close result is ignored
; because this helper is used on both normal EOF and error cleanup paths.
; ------------------------------------------------------------
.proc nbox_ls_close_dir
    lda nbox_dir_fd
    cmp #NBOX_DIR_FD_NONE
    beq @done

    SYSCALL nbox_ls_closedir_args, sys_closedir
    lda #NBOX_DIR_FD_NONE
    sta nbox_dir_fd
    sta nbox_ls_readdir_args + readdir_args::fd
    sta nbox_ls_closedir_args + closedir_args::fd
@done:
    rts
.endproc

; ------------------------------------------------------------
.proc nbox_ls_print_entry
    lda #'-'
    ldx nbox_dir_entry + dir_entry::attr
    txa
    and #NBOX_ATTR_DIR
    beq @type_ready
    lda #'d'
@type_ready:
    sta nbox_ls_type_prefix

    lda #<nbox_ls_type_prefix
    ldx #>nbox_ls_type_prefix
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
.proc nbox_ls_pass_dirs
    SYSCALL nbox_ls_opendir_args, sys_opendir
    bcc @opened
    lda #1
    sec
    rts

@opened:
    sta nbox_dir_fd
    sta nbox_ls_readdir_args + readdir_args::fd
    sta nbox_ls_closedir_args + closedir_args::fd

@loop:
    SYSCALL nbox_ls_readdir_args, sys_readdir
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
.proc nbox_ls_pass_files
    SYSCALL nbox_ls_opendir_args, sys_opendir
    bcc @opened
    lda #1
    sec
    rts

@opened:
    sta nbox_dir_fd
    sta nbox_ls_readdir_args + readdir_args::fd
    sta nbox_ls_closedir_args + closedir_args::fd

@loop:
    SYSCALL nbox_ls_readdir_args, sys_readdir
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

.proc nbox_cmd_ls
    jsr nbox_copy_arg_from_y
    jmp nbox_ls
.endproc

