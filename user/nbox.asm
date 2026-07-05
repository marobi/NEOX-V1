; ============================================================
; nbox.asm
; NEOX - small BusyBox-like applet collection for user space
;
; V38a applets:
;   help
;   pwd
;   cd [path]
;   ls [path]
;
; Parser contract:
;   - command plus one optional argument
;   - input line is already uppercased by task6
;   - spaces and tabs separate command and argument
;   - no quotes, wildcards, redirection, or pipes
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export nbox_line_buf
.export nbox_line_len
.export nbox_dispatch_line
.export nbox_print_prompt

NBOX_LINE_MAX      = 64
NBOX_PATH_MAX      = 64
NBOX_CMD_NAME_MAX  = 4
NBOX_CMD_NAME_SLOT = 5
NBOX_DIR_FD_NONE   = $FF
NBOX_ATTR_DIR      = $10

.segment "USER_DATA"

nbox_line_buf:
    .res NBOX_LINE_MAX

nbox_line_len:
    .byte 0

nbox_arg_buf:
    .res NBOX_PATH_MAX

nbox_arg_len:
    .byte 0

nbox_cwd_buf:
    .res NBOX_PATH_MAX

nbox_dir_entry:
    .res DIR_ENTRY_SIZE

nbox_dir_fd:
    .byte NBOX_DIR_FD_NONE

nbox_cmd_idx:
    .byte 0

nbox_src_idx:
    .byte 0

nbox_dst_idx:
    .byte 0

nbox_tmp_len:
    .byte 0

; Table-driven command parser state.
; This follows the same principle as MICMON: command matching is data-driven,
; then dispatch goes through an indirect vector.
nbox_token_start:
    .byte 0

nbox_line_idx:
    .byte 0

nbox_name_idx:
    .byte 0

nbox_name_offset:
    .byte 0

nbox_jmpvec:
    .word 0

nbox_tmp_char:
    .byte 0

nbox_cmd_buf:
    .res NBOX_CMD_NAME_SLOT

nbox_type_prefix:
    .byte "- "

nbox_cr:
    .byte 13

nbox_arg_dot:
    .byte ".", 0

nbox_arg_root:
    .byte "/", 0

nbox_msg_prompt:
    .byte "0:/> "

nbox_msg_help:
    .byte "COMMANDS: HELP PWD CD LS", 13

nbox_msg_unknown:
    .byte "?", 13

nbox_msg_cd_fail:
    .byte "CD FAIL", 13

nbox_msg_ls_fail:
    .byte "LS FAIL", 13

nbox_msg_readdir_fail:
    .byte "READDIR FAIL", 13

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

.proc nbox_print_prompt
    lda #<nbox_msg_prompt
    ldx #>nbox_msg_prompt
    ldy #5
    jmp nbox_print_msg
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
    ldy #25
    jmp nbox_print_msg
.endproc

.proc nbox_print_unknown
    lda #<nbox_msg_unknown
    ldx #>nbox_msg_unknown
    ldy #2
    jmp nbox_print_msg
.endproc

.proc nbox_print_cd_fail
    lda #<nbox_msg_cd_fail
    ldx #>nbox_msg_cd_fail
    ldy #8
    jmp nbox_print_msg
.endproc

.proc nbox_print_ls_fail
    lda #<nbox_msg_ls_fail
    ldx #>nbox_msg_ls_fail
    ldy #8
    jmp nbox_print_msg
.endproc

.proc nbox_print_readdir_fail
    lda #<nbox_msg_readdir_fail
    ldx #>nbox_msg_readdir_fail
    ldy #13
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
; nbox_is_token_end
;
; Input:
;   Y = line offset
;
; Return:
;   C clear = token end (NUL/space/tab)
;   C set   = not token end
; ------------------------------------------------------------
.proc nbox_is_token_end
    lda nbox_line_buf,y
    beq @yes
    cmp #' '
    beq @yes
    cmp #9
    beq @yes
    sec
    rts
@yes:
    clc
    rts
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
;
; Uses nbox_arg_buf.
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
; nbox_ls
;
; Uses nbox_arg_buf. Empty argument means ".".
; ------------------------------------------------------------
.proc nbox_ls
    jsr nbox_default_arg_dot_if_empty

    SYSCALL nbox_opendir_args, sys_opendir
    bcc @opened
    jmp nbox_print_ls_fail

@opened:
    sta nbox_dir_fd
    sta nbox_readdir_args + readdir_args::fd
    sta nbox_closedir_args + closedir_args::fd

@loop:
    SYSCALL nbox_readdir_args, sys_readdir
    bcc @read_ok

    jsr nbox_print_readdir_fail
    bra @close

@read_ok:
    cmp #0
    bne @entry
    cpx #0
    bne @entry
    bra @close

@entry:
    jsr nbox_ls_print_entry
    bra @loop

@close:
    SYSCALL nbox_closedir_args, sys_closedir
    stz nbox_dir_fd
    clc
    rts
.endproc

; ------------------------------------------------------------
; nbox_find_token_end
;
; Input:
;   Y = command token start
;
; Output:
;   Y = first byte after command token
; ------------------------------------------------------------
.proc nbox_find_token_end
@loop:
    lda nbox_line_buf,y
    beq @done
    cmp #' '
    beq @done
    cmp #9
    beq @done
    iny
    bra @loop
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
;
; Notes:
;   Full-token command matching is used. Single-character aliases are not
;   accepted for shell commands.
; ------------------------------------------------------------
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

    ; Normalize here as well as in task6 so nbox can later be called from
    ; other input paths/processes.
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

    clc
    rts
@no:
    sec
    rts
.endproc

; ------------------------------------------------------------
; Command wrapper procedures.
;
; The dispatcher jumps here with Y positioned just after the command token.
; Commands that take an argument copy it from the line first.
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


; ------------------------------------------------------------
; nbox_skip_prompt_prefix
;
; The RP VDU line editor returns the whole edited screen line. Because task 6
; prints the prompt before input, the returned line can start with "0:/> "
; before the actual command. Skip only a complete drive-root prompt prefix.
;
; Input:
;   Y = current line offset, normally 0
;
; Output:
;   Y = unchanged, or offset just after "N:/>"
;
; Notes:
;   - Empty and too-short lines are safe: no prefix is consumed unless all
;     four prompt bytes are present.
;   - The following blank after the prompt is not consumed here; the normal
;     blank skipper in nbox_dispatch_line handles it.
; ------------------------------------------------------------
.proc nbox_skip_prompt_prefix
    lda nbox_line_buf,y
    cmp #'0'
    bcc @done
    cmp #'9' + 1
    bcs @done

    iny
    lda nbox_line_buf,y
    cmp #':'
    bne @restore0

    iny
    lda nbox_line_buf,y
    cmp #'/'
    bne @restore0

    iny
    lda nbox_line_buf,y
    cmp #'>'
    bne @restore0

    iny
    rts

@restore0:
    ldy #0
@done:
    rts
.endproc

; ------------------------------------------------------------
; nbox_dispatch_line
;
; Table-driven full-token command dispatch:
;   - skip leading blanks
;   - copy the full command token into a small zero-padded buffer
;   - compare that token against a fixed-width command-name table
;   - dispatch through the matching handler vector
;
; Supported commands:
;   HELP
;   PWD
;   CD [path]
;   LS [path]
;
; Single-character aliases are intentionally not supported.
; ------------------------------------------------------------
.proc nbox_dispatch_line
    ldy #0
    jsr nbox_skip_prompt_prefix
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
    .byte "HELP", 0
    .byte "PWD", 0, 0
    .byte "CD", 0, 0, 0
    .byte "LS", 0, 0, 0
    .byte $FF, $FF, $FF, $FF, $FF

nbox_cmd_handlers:
    .word nbox_cmd_help
    .word nbox_cmd_pwd
    .word nbox_cmd_cd
    .word nbox_cmd_ls
