; ============================================================
; neosh.asm
; NEOX - interactive shell loop
;
; Purpose:
;   Interactive shell front-end for task 6.  It owns the prompt,
;   VDU line input, prompt-prefix stripping, shell redirection parsing,
;   and dispatch to nbox.
;
; Commands are implemented in user/nbox.asm.
;
; Input policy:
;   - RP VDU owns line editing and echo
;   - neosh reads one complete edited line with SYS_READ
;   - if the returned line starts with the prompt neosh printed, neosh strips
;     that prompt before calling nbox
;   - neosh removes shell redirection operators and filenames before
;     passing the command line to nbox
;   - stdin, stdout, and stderr redirection are executed for resident
;     child commands
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "nbox.inc"

.export neosh_main

.import nbox_line_buf
.import nbox_line_len
.import nbox_dispatch_line
.import nbox_resolve_line
.import nbox_child_entry
.import nbox_exec_mode
.import nbox_launch_id
.import nbox_line_idx
.import nbox_arg_buf
.import nbox_arg2_buf
.import nbox_arg_len
.import nbox_arg2_len
.import nbox_copy_two_args_from_y
.import nbox_print_unknown

NEOSH_RX_FD        = STDIN
NEOSH_LINE_MAX     = 64
NEOSH_PROMPT_MAX   = 64

NEOSH_REDIR_NONE   = $00
NEOSH_REDIR_READ   = $01
NEOSH_REDIR_TRUNC  = $02
NEOSH_REDIR_APPEND = $03

.segment "USER_DATA"

neosh_raw_line_buf:
    .res NEOSH_LINE_MAX

neosh_prompt_buf:
    .res NEOSH_PROMPT_MAX

neosh_cwd_buf:
    .res NEOSH_PROMPT_MAX

neosh_raw_len:
    .res 1

neosh_prompt_core_len:
    .res 1

neosh_src_idx:
    .res 1

neosh_dst_idx:
    .res 1

neosh_cmp_idx:
    .res 1

neosh_tmp:
    .res 1

; Parsed command line after shell-owned redirection tokens are removed.
neosh_command_buf:
    .res NEOSH_LINE_MAX

; One redirection target per standard descriptor.
neosh_stdin_path:
    .res NEOSH_LINE_MAX

neosh_stdout_path:
    .res NEOSH_LINE_MAX

neosh_stderr_path:
    .res NEOSH_LINE_MAX

neosh_stdin_path_len:
    .res 1

neosh_stdout_path_len:
    .res 1

neosh_stderr_path_len:
    .res 1

neosh_stdin_mode:
    .res 1

neosh_stdout_mode:
    .res 1

neosh_stderr_mode:
    .res 1

neosh_redir_seen:
    .res 1

; Redirection parser scratch.
neosh_parse_src_idx:
    .res 1

neosh_parse_dst_idx:
    .res 1

neosh_token_start:
    .res 1

neosh_token_len:
    .res 1

neosh_redir_fd_tmp:
    .res 1

neosh_redir_mode_tmp:
    .res 1

neosh_redir_op_len:
    .res 1

neosh_pending_fd:
    .res 1

neosh_pending_mode:
    .res 1

neosh_path_start:
    .res 1

neosh_path_len:
    .res 1

neosh_prompt_tail:
    .byte "> "

neosh_cr:
    .byte 13

neosh_msg_redir_error:
    .byte "REDIR?", 13
NEOSH_MSG_REDIR_ERROR_LEN = * - neosh_msg_redir_error

neosh_default_prompt:
    .byte "0:/> "

neosh_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

neosh_read_args:
    .byte NEOSH_RX_FD
    .byte 0
    .word neosh_raw_line_buf
    .word NEOSH_LINE_MAX - 1

neosh_getcwd_args:
    .word neosh_cwd_buf
    .word NEOSH_PROMPT_MAX - 2
    .word 0
    .byte NEOX_PATH_FLAGS_NONE
    .byte 0

neosh_spawn_child_pid:
    .byte $FF

neosh_spawn_argc:
    .byte 0

; Temporary shell descriptors used as sources for child fd 0/1/2.
neosh_stdin_redir_fd:
    .byte SPAWN_FD_CLOSED

neosh_stdout_redir_fd:
    .byte SPAWN_FD_CLOSED

neosh_stderr_redir_fd:
    .byte SPAWN_FD_CLOSED

; Shared argument blocks used while opening one redirection target.
neosh_redir_open_args:
    .word 0
    .word NEOSH_LINE_MAX
    .byte OPEN_READ
    .byte 0

neosh_redir_seek_args:
    .byte SPAWN_FD_CLOSED
    .byte SEEK_END
    .word 0
    .word 0
    .word 0
    .word 0

neosh_exec_redir_fd:
    .byte SPAWN_FD_CLOSED

neosh_exec_redir_mode:
    .byte NEOSH_REDIR_NONE

neosh_spawn_args:
    .word nbox_child_entry
    .byte NBOX_APPLET_NONE
    .byte 0
    .word nbox_arg_buf
    .byte 0
    .word nbox_arg2_buf
    .byte 0
    .byte STDIN
    .byte STDOUT
    .byte STDERR
    .byte SPAWN_FLAGS_NONE
    .byte $FF

.segment "USER_TEXT"

; ------------------------------------------------------------
; neosh_print_msg
;
; Input:
;   A/X = buffer pointer
;   Y   = byte count
; ------------------------------------------------------------
.proc neosh_print_msg
    sta neosh_stdout_args + rw_args::buf_ptr
    stx neosh_stdout_args + rw_args::buf_ptr + 1

    tya
    sta neosh_stdout_args + rw_args::len
    stz neosh_stdout_args + rw_args::len + 1

    SYSCALL neosh_stdout_args, sys_write
    rts
.endproc

; ------------------------------------------------------------
; neosh_print_default_prompt
; ------------------------------------------------------------
.proc neosh_print_default_prompt
    lda #<neosh_default_prompt
    ldx #>neosh_default_prompt
    ldy #5
    jmp neosh_print_msg
.endproc

; ------------------------------------------------------------
; neosh_build_prompt
;
; Builds prompt_buf = getcwd() + "> ".  prompt_core_len is the length of
; getcwd() + ">" and is used for stripping returned VDU lines.
;
; Return:
;   C clear = prompt built
;   C set   = fallback/default prompt should be used
; ------------------------------------------------------------
.proc neosh_build_prompt
    SYSCALL neosh_getcwd_args, sys_getcwd
    bcc @got_cwd
    sec
    rts

@got_cwd:
    ; A = cwd length excluding NUL.  Keep the prompt within NEOSH_PROMPT_MAX.
    cmp #NEOSH_PROMPT_MAX - 2
    bcc @len_ok
    beq @len_ok
    sec
    rts

@len_ok:
    sta neosh_tmp
    tay
    beq @copy_done

    ldy #0
@copy_loop:
    cpy neosh_tmp
    beq @copy_done
    lda neosh_cwd_buf,y
    sta neosh_prompt_buf,y
    iny
    bra @copy_loop

@copy_done:
    ldy neosh_tmp
    lda #'>'
    sta neosh_prompt_buf,y
    iny
    sty neosh_prompt_core_len

    lda #' '
    sta neosh_prompt_buf,y
    iny

    ; Return prompt byte count in Y for caller print.
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_print_prompt
; ------------------------------------------------------------
.proc neosh_print_prompt
    jsr neosh_build_prompt
    bcc @print_dynamic
    jmp neosh_print_default_prompt

@print_dynamic:
    lda #<neosh_prompt_buf
    ldx #>neosh_prompt_buf
    ; Y is set by neosh_build_prompt to full prompt length.
    jmp neosh_print_msg
.endproc

; ------------------------------------------------------------
; neosh_read_line
;
; Reads one complete VDU-edited line.  The RP VDU path owns editing/echo.
;
; Return:
;   C clear = line available, neosh_raw_len contains low byte count
;   C set   = read failed
; ------------------------------------------------------------
.proc neosh_read_line
    SYSCALL neosh_read_args, sys_read
    bcc @ok
    sec
    rts

@ok:
    ; For this buffer X should be zero.  If not, cap as full buffer.
    cpx #0
    beq @store_len
    lda #NEOSH_LINE_MAX - 1

@store_len:
    cmp #NEOSH_LINE_MAX
    bcc @len_ready
    lda #NEOSH_LINE_MAX - 1

@len_ready:
    sta neosh_raw_len
    tax
    lda #0
    sta neosh_raw_line_buf,x
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_raw_starts_with_prompt
;
; Return:
;   C clear = raw line starts with prompt core getcwd()+">"
;   C set   = no prompt prefix
; ------------------------------------------------------------
.proc neosh_raw_starts_with_prompt
    lda neosh_prompt_core_len
    beq @no
    cmp neosh_raw_len
    bcc @enough
    beq @enough
    bra @no

@enough:
    stz neosh_cmp_idx
@loop:
    ldy neosh_cmp_idx
    cpy neosh_prompt_core_len
    beq @yes
    lda neosh_raw_line_buf,y
    and #$7F
    cmp neosh_prompt_buf,y
    bne @no
    inc neosh_cmp_idx
    bra @loop

@yes:
    clc
    rts
@no:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_select_command_start
;
; Sets neosh_src_idx to the start of command text.
; ------------------------------------------------------------
.proc neosh_select_command_start
    stz neosh_src_idx

    jsr neosh_raw_starts_with_prompt
    bcs @skip_spaces

    lda neosh_prompt_core_len
    sta neosh_src_idx

@skip_spaces:
    ldy neosh_src_idx
    lda neosh_raw_line_buf,y
    and #$7F
    cmp #' '
    beq @next
    cmp #9
    beq @next
    rts
@next:
    inc neosh_src_idx
    bra @skip_spaces
.endproc

; ------------------------------------------------------------
; neosh_copy_clean_line_to_nbox
;
; Copies raw VDU line to nbox_line_buf after optional prompt stripping.
; It also normalizes to 7-bit uppercase ASCII and strips CR/LF.
; ------------------------------------------------------------
.proc neosh_copy_clean_line_to_nbox
    jsr neosh_select_command_start
    stz neosh_dst_idx

@loop:
    ldy neosh_src_idx
    cpy neosh_raw_len
    bcs @done

    lda neosh_raw_line_buf,y
    and #$7F
    beq @done
    cmp #13
    beq @done
    cmp #10
    beq @done

    ; Uppercase a-z.
    cmp #'a'
    bcc @upper_ready
    cmp #'z' + 1
    bcs @upper_ready
    sec
    sbc #$20

@upper_ready:
    ldx neosh_dst_idx
    cpx #NEOSH_LINE_MAX - 1
    bcs @done
    sta nbox_line_buf,x
    inc neosh_dst_idx
    inc neosh_src_idx
    bra @loop

@done:
    ldx neosh_dst_idx
    lda #0
    sta nbox_line_buf,x
    stx nbox_line_len
    rts
.endproc


; ------------------------------------------------------------
; neosh_reset_redirection_plan
;
; Clears the shell-owned descriptor plan before parsing a new line.
; ------------------------------------------------------------
.proc neosh_reset_redirection_plan
    stz neosh_stdin_mode
    stz neosh_stdout_mode
    stz neosh_stderr_mode

    stz neosh_stdin_path_len
    stz neosh_stdout_path_len
    stz neosh_stderr_path_len

    stz neosh_stdin_path
    stz neosh_stdout_path
    stz neosh_stderr_path

    stz neosh_redir_seen
    stz neosh_parse_src_idx
    stz neosh_parse_dst_idx

    lda #STDIN
    sta neosh_spawn_args + spawn_resident_args::stdin_fd

    lda #STDOUT
    sta neosh_spawn_args + spawn_resident_args::stdout_fd

    lda #STDERR
    sta neosh_spawn_args + spawn_resident_args::stderr_fd

    lda #SPAWN_FD_CLOSED
    sta neosh_stdin_redir_fd
    sta neosh_stdout_redir_fd
    sta neosh_stderr_redir_fd
    sta neosh_redir_seek_args + seek_args::fd
    sta neosh_exec_redir_fd

    stz neosh_exec_redir_mode
    rts
.endproc

; ------------------------------------------------------------
; neosh_parse_next_token
;
; Reads the next whitespace-separated token from nbox_line_buf.
;
; Return:
;   C clear = token found
;             neosh_token_start/len describe it
;             neosh_parse_src_idx points at its end
;   C set   = no more tokens
; ------------------------------------------------------------
.proc neosh_parse_next_token
@skip:
    ldy neosh_parse_src_idx
    lda nbox_line_buf,y
    beq @none
    cmp #' '
    beq @skip_one
    cmp #9
    beq @skip_one
    bra @start

@skip_one:
    inc neosh_parse_src_idx
    bra @skip

@start:
    sty neosh_token_start
    stz neosh_token_len

@scan:
    lda nbox_line_buf,y
    beq @done
    cmp #' '
    beq @done
    cmp #9
    beq @done

    inc neosh_token_len
    iny
    bra @scan

@done:
    sty neosh_parse_src_idx
    clc
    rts

@none:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_classify_redirection
;
; Classifies the current token.
;
; Recognized forms:
;   <     <FILE
;   >     >FILE
;   >>    >>FILE
;   2>    2>FILE
;   2>>   2>>FILE
;
; Return:
;   C clear = redirection operator
;             fd/mode/operator length stored in parser scratch
;   C set   = ordinary command/argument token
; ------------------------------------------------------------
.proc neosh_classify_redirection
    ldy neosh_token_start
    lda nbox_line_buf,y

    cmp #'<'
    beq @stdin

    cmp #'>'
    beq @stdout

    cmp #'2'
    bne @ordinary

    lda neosh_token_len
    cmp #2
    bcc @ordinary

    iny
    lda nbox_line_buf,y
    cmp #'>'
    bne @ordinary

    lda #STDERR
    sta neosh_redir_fd_tmp

    lda #NEOSH_REDIR_TRUNC
    sta neosh_redir_mode_tmp

    lda #2
    sta neosh_redir_op_len

    lda neosh_token_len
    cmp #3
    bcc @recognized

    iny
    lda nbox_line_buf,y
    cmp #'>'
    bne @recognized

    lda #NEOSH_REDIR_APPEND
    sta neosh_redir_mode_tmp

    lda #3
    sta neosh_redir_op_len
    bra @recognized

@stdin:
    lda #STDIN
    sta neosh_redir_fd_tmp

    lda #NEOSH_REDIR_READ
    sta neosh_redir_mode_tmp

    lda #1
    sta neosh_redir_op_len
    bra @recognized

@stdout:
    lda #STDOUT
    sta neosh_redir_fd_tmp

    lda #NEOSH_REDIR_TRUNC
    sta neosh_redir_mode_tmp

    lda #1
    sta neosh_redir_op_len

    lda neosh_token_len
    cmp #2
    bcc @recognized

    iny
    lda nbox_line_buf,y
    cmp #'>'
    bne @recognized

    lda #NEOSH_REDIR_APPEND
    sta neosh_redir_mode_tmp

    lda #2
    sta neosh_redir_op_len

@recognized:
    clc
    rts

@ordinary:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_copy_token_to_command
;
; Appends the current ordinary token to neosh_command_buf, normalizing
; inter-token whitespace to one space.
; ------------------------------------------------------------
.proc neosh_copy_token_to_command
    lda neosh_parse_dst_idx
    beq @copy

    tax
    lda #' '
    sta neosh_command_buf,x
    inc neosh_parse_dst_idx

@copy:
    ldx neosh_token_start
    ldy #0

@loop:
    cpy neosh_token_len
    beq @done

    lda nbox_line_buf,x
    phy
    ldy neosh_parse_dst_idx
    sta neosh_command_buf,y
    inc neosh_parse_dst_idx
    ply

    inx
    iny
    bra @loop

@done:
    rts
.endproc

; ------------------------------------------------------------
; neosh_store_pending_redirection
;
; Copies the selected pathname to the descriptor plan and records its
; mode. Duplicate redirection of one descriptor is rejected.
;
; Return:
;   C clear = stored
;   C set   = duplicate/invalid descriptor
; ------------------------------------------------------------
.proc neosh_store_pending_redirection
    lda neosh_pending_fd
    cmp #STDIN
    beq @stdin

    cmp #STDOUT
    beq @stdout

    cmp #STDERR
    beq @stderr

    sec
    rts

@stdin:
    lda neosh_stdin_mode
    beq @stdin_unused
    jmp @fail

@stdin_unused:
    lda neosh_pending_mode
    cmp #NEOSH_REDIR_READ
    beq @stdin_mode_ok
    jmp @fail

@stdin_mode_ok:
    sta neosh_stdin_mode

    ldx neosh_path_start
    ldy #0
@copy_stdin:
    cpy neosh_path_len
    beq @done_stdin
    lda nbox_line_buf,x
    sta neosh_stdin_path,y
    inx
    iny
    bra @copy_stdin

@done_stdin:
    lda #0
    sta neosh_stdin_path,y
    sty neosh_stdin_path_len
    bra @stored

@stdout:
    lda neosh_stdout_mode
    bne @fail

    lda neosh_pending_mode
    cmp #NEOSH_REDIR_TRUNC
    beq @stdout_mode_ok
    cmp #NEOSH_REDIR_APPEND
    bne @fail

@stdout_mode_ok:
    sta neosh_stdout_mode

    ldx neosh_path_start
    ldy #0
@copy_stdout:
    cpy neosh_path_len
    beq @done_stdout
    lda nbox_line_buf,x
    sta neosh_stdout_path,y
    inx
    iny
    bra @copy_stdout

@done_stdout:
    lda #0
    sta neosh_stdout_path,y
    sty neosh_stdout_path_len
    bra @stored

@stderr:
    lda neosh_stderr_mode
    bne @fail

    lda neosh_pending_mode
    cmp #NEOSH_REDIR_TRUNC
    beq @stderr_mode_ok
    cmp #NEOSH_REDIR_APPEND
    bne @fail

@stderr_mode_ok:
    sta neosh_stderr_mode

    ldx neosh_path_start
    ldy #0
@copy_stderr:
    cpy neosh_path_len
    beq @done_stderr
    lda nbox_line_buf,x
    sta neosh_stderr_path,y
    inx
    iny
    bra @copy_stderr

@done_stderr:
    lda #0
    sta neosh_stderr_path,y
    sty neosh_stderr_path_len

@stored:
    lda #1
    sta neosh_redir_seen
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_capture_redirection
;
; Captures an inline pathname or consumes the next token as pathname.
;
; Return:
;   C clear = captured
;   C set   = pathname missing or invalid
; ------------------------------------------------------------
.proc neosh_capture_redirection
    lda neosh_redir_fd_tmp
    sta neosh_pending_fd

    lda neosh_redir_mode_tmp
    sta neosh_pending_mode

    lda neosh_token_len
    cmp neosh_redir_op_len
    beq @separate_path

    sec
    sbc neosh_redir_op_len
    sta neosh_path_len

    clc
    lda neosh_token_start
    adc neosh_redir_op_len
    sta neosh_path_start

    jmp neosh_store_pending_redirection

@separate_path:
    jsr neosh_parse_next_token
    bcs @fail

    ; A following redirection operator is not a pathname.
    jsr neosh_classify_redirection
    bcc @fail

    lda neosh_token_start
    sta neosh_path_start

    lda neosh_token_len
    beq @fail
    sta neosh_path_len

    jmp neosh_store_pending_redirection

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_copy_parsed_command_to_nbox
;
; Commits the compact command/argument line to nbox_line_buf.
; ------------------------------------------------------------
.proc neosh_copy_parsed_command_to_nbox
    ldy #0

@copy:
    cpy neosh_parse_dst_idx
    beq @done

    lda neosh_command_buf,y
    sta nbox_line_buf,y
    iny
    bra @copy

@done:
    lda #0
    sta nbox_line_buf,y
    sty nbox_line_len
    rts
.endproc

; ------------------------------------------------------------
; neosh_parse_redirections
;
; Builds one shell execution descriptor:
;   compact command/argument line
;   stdin source
;   stdout destination and mode
;   stderr destination and mode
;
; Redirection tokens and their pathnames are removed from the command
; line before it is returned to nbox.
;
; Return:
;   C clear = valid command plan
;   C set   = malformed or duplicate redirection
; ------------------------------------------------------------
.proc neosh_parse_redirections
    jsr neosh_reset_redirection_plan

@next:
    jsr neosh_parse_next_token
    bcs @finished

    jsr neosh_classify_redirection
    bcc @redirection

    jsr neosh_copy_token_to_command
    jmp @next

@redirection:
    jsr neosh_capture_redirection
    bcs @fail
    jmp @next

@finished:
    ldy neosh_parse_dst_idx
    lda #0
    sta neosh_command_buf,y

    ; A descriptor plan without a command is invalid.
    cpy #0
    bne @commit

    lda neosh_redir_seen
    bne @fail

@commit:
    jsr neosh_copy_parsed_command_to_nbox
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_print_redirection_error
; ------------------------------------------------------------
.proc neosh_print_redirection_error
    lda #<neosh_msg_redir_error
    ldx #>neosh_msg_redir_error
    ldy #NEOSH_MSG_REDIR_ERROR_LEN
    jmp neosh_print_msg
.endproc


; ------------------------------------------------------------
; neosh_close_redirections
;
; Closes all temporary parent descriptors and restores normal child
; mappings. Close errors do not prevent the remaining descriptors from
; being released.
; ------------------------------------------------------------
.proc neosh_close_redirections
    lda #STDIN
    sta neosh_spawn_args + spawn_resident_args::stdin_fd

    lda neosh_stdin_redir_fd
    cmp #SPAWN_FD_CLOSED
    beq @stdout

    pha
    lda #SPAWN_FD_CLOSED
    sta neosh_stdin_redir_fd
    pla
    jsr sys_close

@stdout:
    lda #STDOUT
    sta neosh_spawn_args + spawn_resident_args::stdout_fd

    lda neosh_stdout_redir_fd
    cmp #SPAWN_FD_CLOSED
    beq @stderr

    pha
    lda #SPAWN_FD_CLOSED
    sta neosh_stdout_redir_fd
    pla
    jsr sys_close

@stderr:
    lda #STDERR
    sta neosh_spawn_args + spawn_resident_args::stderr_fd

    lda neosh_stderr_redir_fd
    cmp #SPAWN_FD_CLOSED
    beq @done

    pha
    lda #SPAWN_FD_CLOSED
    sta neosh_stderr_redir_fd
    pla
    jsr sys_close

@done:
    lda #SPAWN_FD_CLOSED
    sta neosh_redir_seek_args + seek_args::fd
    sta neosh_exec_redir_fd

    stz neosh_exec_redir_mode
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_install_opened_redirection
;
; Input:
;   A = temporary shell fd returned by sys_open
;
; Uses neosh_exec_redir_fd to install the descriptor as the source for
; child stdin, stdout, or stderr.
;
; Return:
;   C clear = installed
;   C set   = invalid target descriptor
; ------------------------------------------------------------
.proc neosh_install_opened_redirection
    pha

    lda neosh_exec_redir_fd
    cmp #STDIN
    beq @stdin

    cmp #STDOUT
    beq @stdout

    cmp #STDERR
    beq @stderr

    pla
    sec
    rts

@stdin:
    pla
    sta neosh_stdin_redir_fd
    sta neosh_spawn_args + spawn_resident_args::stdin_fd
    clc
    rts

@stdout:
    pla
    sta neosh_stdout_redir_fd
    sta neosh_spawn_args + spawn_resident_args::stdout_fd
    clc
    rts

@stderr:
    pla
    sta neosh_stderr_redir_fd
    sta neosh_spawn_args + spawn_resident_args::stderr_fd
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_open_current_redirection
;
; Opens one pathname selected in neosh_redir_open_args.
;
; neosh_exec_redir_fd:
;   STDIN, STDOUT, or STDERR
;
; neosh_exec_redir_mode:
;   NEOSH_REDIR_READ, NEOSH_REDIR_TRUNC, or NEOSH_REDIR_APPEND
;
; Return:
;   C clear = opened and mapped
;   C set   = invalid plan or filesystem failure
; ------------------------------------------------------------
.proc neosh_open_current_redirection
    lda neosh_exec_redir_mode
    cmp #NEOSH_REDIR_READ
    beq @read

    cmp #NEOSH_REDIR_TRUNC
    beq @truncate

    cmp #NEOSH_REDIR_APPEND
    beq @append

    sec
    rts

@read:
    lda neosh_exec_redir_fd
    cmp #STDIN
    beq @read_ok
    sec
    rts

@read_ok:
    lda #OPEN_READ
    sta neosh_redir_open_args + open_args::flags
    bra @open

@truncate:
    lda neosh_exec_redir_fd
    cmp #STDOUT
    beq @write_trunc
    cmp #STDERR
    beq @write_trunc
    sec
    rts

@write_trunc:
    lda #OPEN_WRITE_TRUNC
    sta neosh_redir_open_args + open_args::flags
    bra @open

@append:
    lda neosh_exec_redir_fd
    cmp #STDOUT
    beq @write_append
    cmp #STDERR
    beq @write_append
    sec
    rts

@write_append:
    ; OPEN_RW_CREATE preserves an existing file and creates an absent
    ; file. SEEK_END establishes the initial append position.
    lda #OPEN_RW_CREATE
    sta neosh_redir_open_args + open_args::flags

@open:
    SYSCALL neosh_redir_open_args, sys_open
    bcc @opened

    sec
    rts

@opened:
    sta neosh_redir_seek_args + seek_args::fd
    jsr neosh_install_opened_redirection
    bcc @installed

    ; Invalid target: close the descriptor returned by sys_open.
    lda neosh_redir_seek_args + seek_args::fd
    jsr sys_close
    sec
    rts

@installed:
    lda neosh_exec_redir_mode
    cmp #NEOSH_REDIR_APPEND
    beq @seek_end

    clc
    rts

@seek_end:
    SYSCALL neosh_redir_seek_args, sys_seek
    bcc @ready

    jsr neosh_close_redirections
    sec
    rts

@ready:
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_select_redirection_path
;
; Input:
;   A = STDIN, STDOUT, or STDERR
;
; Selects the matching path and mode for neosh_open_current_redirection.
;
; Return:
;   C clear = selected
;   C set   = invalid target or no redirection for target
; ------------------------------------------------------------
.proc neosh_select_redirection_path
    sta neosh_exec_redir_fd

    cmp #STDIN
    beq @stdin

    cmp #STDOUT
    beq @stdout

    cmp #STDERR
    beq @stderr

    sec
    rts

@stdin:
    lda neosh_stdin_mode
    beq @none
    sta neosh_exec_redir_mode

    lda #<neosh_stdin_path
    sta neosh_redir_open_args + open_args::path_ptr
    lda #>neosh_stdin_path
    sta neosh_redir_open_args + open_args::path_ptr + 1
    clc
    rts

@stdout:
    lda neosh_stdout_mode
    beq @none
    sta neosh_exec_redir_mode

    lda #<neosh_stdout_path
    sta neosh_redir_open_args + open_args::path_ptr
    lda #>neosh_stdout_path
    sta neosh_redir_open_args + open_args::path_ptr + 1
    clc
    rts

@stderr:
    lda neosh_stderr_mode
    beq @none
    sta neosh_exec_redir_mode

    lda #<neosh_stderr_path
    sta neosh_redir_open_args + open_args::path_ptr
    lda #>neosh_stderr_path
    sta neosh_redir_open_args + open_args::path_ptr + 1
    clc
    rts

@none:
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_open_redirections
;
; Opens all requested redirections and installs child fd mappings.
; The operation is transactional from the shell's perspective: any
; failure closes every descriptor opened so far.
;
; Return:
;   C clear = all mappings ready
;   C set   = invalid plan or filesystem failure
; ------------------------------------------------------------
.proc neosh_open_redirections
    lda neosh_stdin_mode
    beq @stdout

    lda #STDIN
    jsr neosh_select_redirection_path
    bcs @fail
    jsr neosh_open_current_redirection
    bcs @fail

@stdout:
    lda neosh_stdout_mode
    beq @stderr

    lda #STDOUT
    jsr neosh_select_redirection_path
    bcs @fail
    jsr neosh_open_current_redirection
    bcs @fail

@stderr:
    lda neosh_stderr_mode
    beq @done

    lda #STDERR
    jsr neosh_select_redirection_path
    bcs @fail
    jsr neosh_open_current_redirection
    bcs @fail

@done:
    clc
    rts

@fail:
    jsr neosh_close_redirections
    sec
    rts
.endproc

; ------------------------------------------------------------
; neosh_prepare_spawn_args
;
; Uses the resolved nbox_line_idx to copy up to two command arguments
; into the normal nbox argument buffers, then derives argc for the
; compact resident spawn argument ABI.
; ------------------------------------------------------------
.proc neosh_prepare_spawn_args
    ldy nbox_line_idx
    jsr nbox_copy_two_args_from_y

    lda nbox_arg_len
    beq @argc0

    lda nbox_arg2_len
    beq @argc1

    lda #2
    bra @store

@argc1:
    lda #1
    bra @store

@argc0:
    lda #0

@store:
    sta neosh_spawn_argc
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_spawn_resolved_child
;
; Spawn the already-resolved nbox command as a resident child, using
; the launch id and up to two copied arguments.  Normal stdin/stdout/
; stderr mapping is part of the unified SYS_SPAWN_RESIDENT transaction.
;
; Return:
;   C clear = child completed and was reaped
;   C set   = spawn/setup/commit/wait failed
; ------------------------------------------------------------
.proc neosh_spawn_resolved_child
    jsr neosh_prepare_spawn_args

    lda nbox_launch_id
    sta neosh_spawn_args + spawn_resident_args::launch_id

    lda neosh_spawn_argc
    sta neosh_spawn_args + spawn_resident_args::argc

    lda nbox_arg_len
    sta neosh_spawn_args + spawn_resident_args::arg0_len

    lda nbox_arg2_len
    sta neosh_spawn_args + spawn_resident_args::arg1_len

    SYSCALL neosh_spawn_args, sys_spawn_resident
    bcc @spawned

    jsr neosh_close_redirections
    sec
    rts

@spawned:
    sta neosh_spawn_child_pid

    ; The child now owns cloned references to all redirected objects.
    jsr neosh_close_redirections

    lda neosh_spawn_child_pid
    jsr sys_waitpid
    bcc @wait_ok
    sec
    rts

@wait_ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; neosh_execute_clean_line
;
; Uses nbox execution-mode metadata.  Parent-mode commands execute in
; the shell process.  Child-mode commands are spawned as resident nbox
; children and waited for by the shell.
; ------------------------------------------------------------
.proc neosh_execute_clean_line
    jsr nbox_resolve_line
    bcc @resolved
    jmp nbox_print_unknown

@resolved:
    lda nbox_exec_mode
    cmp #NBOX_EXEC_NONE
    beq @done

    cmp #NBOX_EXEC_PARENT
    beq @parent

    cmp #NBOX_EXEC_CHILD
    beq @child

    jmp nbox_print_unknown

@parent:
    lda neosh_redir_seen
    beq @run_parent
    jmp neosh_print_redirection_error

@run_parent:
    jsr nbox_dispatch_line
    clc
    rts

@child:
    lda neosh_redir_seen
    beq @spawn

    jsr neosh_open_redirections
    bcc @spawn
    jmp neosh_print_redirection_error

@spawn:
    jsr neosh_spawn_resolved_child
    bcc @done

    lda neosh_redir_seen
    beq @spawn_unknown
    jmp neosh_print_redirection_error

@spawn_unknown:
    jmp nbox_print_unknown

@done:
    clc
    rts
.endproc

.proc neosh_main
@prompt:
    jsr neosh_print_prompt

@loop:
    jsr neosh_read_line
    bcs @loop

    jsr neosh_copy_clean_line_to_nbox
    jsr neosh_parse_redirections
    bcs @redir_error

    jsr neosh_execute_clean_line
    bra @prompt

@redir_error:
    jsr neosh_print_redirection_error
    bra @prompt
.endproc
