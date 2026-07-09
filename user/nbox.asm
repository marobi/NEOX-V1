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

.import nbox_help
.import nbox_pwd
.import nbox_cd
.import nbox_ls
.import nbox_cat
.import nbox_rm
.import nbox_mv
.import nbox_mkdir
.import nbox_rmdir
.import nbox_cp
.import nbox_ps

.import nbox_src_idx
.import nbox_dst_idx

.export nbox_line_buf
.export nbox_line_len
.export nbox_dispatch_line
.export nbox_resolve_line
.export nbox_child_entry
.export nbox_exec_mode
.export nbox_launch_id
.export nbox_line_idx

.export nbox_arg_buf
.export nbox_arg2_buf
.export nbox_arg_len
.export nbox_arg2_len
.export nbox_print_msg
.export nbox_print_cr
.export nbox_print_help
.export nbox_print_unknown
.export nbox_print_arg_fail
.export nbox_print_space
.export nbox_print_hex_byte
.export nbox_copy_arg_from_y
.export nbox_copy_two_args_from_y
.export nbox_require_arg
.export nbox_require_two_args
.export nbox_default_arg_dot_if_empty
.export nbox_default_arg_root_if_empty

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

nbox_child_get_args:
    .word nbox_arg_buf
    .byte NBOX_PATH_MAX
    .word nbox_arg2_buf
    .byte NBOX_PATH_MAX
    .byte 0          ; argc_out
    .byte 0          ; arg0_len_out
    .byte 0          ; arg1_len_out

nbox_cmd_idx:
    .byte 0

nbox_name_offset:
    .byte 0

nbox_jmpvec:
    .word 0

nbox_exec_mode:
    .byte NBOX_EXEC_NONE

nbox_launch_id:
    .byte NBOX_APPLET_NONE

nbox_line_idx:
    .byte 0

nbox_cmd_buf:
    .res NBOX_CMD_NAME_SLOT

nbox_hex_byte:
    .byte 0

nbox_hex_buf:
    .res 2

nbox_cr:
    .byte 13

nbox_msg_help:
    .byte "COMMANDS: HELP PWD CD LS CAT RM MV MKDIR RMDIR CP PS", 13
NBOX_MSG_HELP_LEN = * - nbox_msg_help

nbox_msg_unknown:
    .byte "?", 13
NBOX_MSG_UNKNOWN_LEN = * - nbox_msg_unknown

nbox_space:
    .byte " "

nbox_hex_digits:
    .byte "0123456789ABCDEF"

nbox_msg_arg_fail:
    .byte "ARG?", 13
NBOX_MSG_ARG_FAIL_LEN = * - nbox_msg_arg_fail

nbox_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

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
; nbox_resolve_line
;
; Resolves the clean command line into the current nbox command metadata.
; This does not execute the command.  The resolver is shared by the direct
; dispatcher and by neosh when it decides whether a command must execute in
; the parent process or in a spawned resident child.
;
; Return:
;   C clear = resolved or empty line
;       nbox_exec_mode = NBOX_EXEC_PARENT / CHILD / NONE
;       nbox_launch_id = NBOX_APPLET_* or NBOX_APPLET_NONE
;       nbox_jmpvec    = direct handler for parent execution
;       nbox_line_idx  = offset just after command token
;   C set = unknown/invalid command
;       nbox_exec_mode = NBOX_EXEC_UNKNOWN
; ------------------------------------------------------------
.proc nbox_resolve_line
    lda #NBOX_EXEC_UNKNOWN
    sta nbox_exec_mode
    lda #NBOX_APPLET_NONE
    sta nbox_launch_id
    stz nbox_jmpvec
    stz nbox_jmpvec+1

    ldy #0
@skip:
    lda nbox_line_buf,y
    bne @not_empty
    lda #NBOX_EXEC_NONE
    sta nbox_exec_mode
    clc
    rts
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
    sec
    rts

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
    ldx nbox_cmd_idx
    lda nbox_cmd_exec_modes,x
    sta nbox_exec_mode
    lda nbox_cmd_launch_ids,x
    sta nbox_launch_id

    lda nbox_cmd_idx
    asl
    tax
    lda nbox_cmd_handlers,x
    sta nbox_jmpvec
    inx
    lda nbox_cmd_handlers,x
    sta nbox_jmpvec+1

    clc
    rts

@unknown:
    lda #NBOX_EXEC_UNKNOWN
    sta nbox_exec_mode
    lda #NBOX_APPLET_NONE
    sta nbox_launch_id
    sec
    rts
.endproc

; ------------------------------------------------------------
; nbox_dispatch_line
; ------------------------------------------------------------
.proc nbox_dispatch_line
    jsr nbox_resolve_line
    bcc @resolved
    jmp nbox_print_unknown

@resolved:
    lda nbox_exec_mode
    cmp #NBOX_EXEC_NONE
    beq @done

    ldy nbox_line_idx
    jmp (nbox_jmpvec)

@done:
    clc
    rts
.endproc

; ------------------------------------------------------------
; nbox_clear_child_args
;
; Prepare an empty argument environment for nbox_child_entry.
; ------------------------------------------------------------
.proc nbox_clear_child_args
    stz nbox_line_buf
    stz nbox_line_len
    stz nbox_arg_buf
    stz nbox_arg2_buf
    stz nbox_arg_len
    stz nbox_arg2_len
    rts
.endproc

; ------------------------------------------------------------
; nbox_load_child_args
;
; Load argc/arg0/arg1 from the kernel launch state into the normal nbox
; applet argument buffers. This keeps existing applets unchanged.
; ------------------------------------------------------------
.proc nbox_load_child_args
    jsr nbox_clear_child_args
    SYSCALL nbox_child_get_args, sys_get_launch_args2
    bcc @ok

    sec
    rts

@ok:
    lda nbox_child_get_args + spawn_get_args2_args::arg0_len_out
    sta nbox_arg_len
    lda nbox_child_get_args + spawn_get_args2_args::arg1_len_out
    sta nbox_arg2_len
    clc
    rts
.endproc

; ------------------------------------------------------------
; nbox_child_entry
;
; Resident child process entry. The parent configured launch id and up
; to two arguments while the process was still PROC_SETUP. The child
; loads that launch state, dispatches one resident applet, then exits.
; ------------------------------------------------------------
.proc nbox_child_entry
    jsr sys_get_launch_id
    bcc @have_id

    lda #EINVAL
    jmp sys_exit

@have_id:
    pha
    jsr nbox_load_child_args
    bcc @args_ok

    pla
    lda #EINVAL
    jmp sys_exit

@args_ok:
    pla

    cmp #NBOX_APPLET_HELP
    beq @help
    cmp #NBOX_APPLET_PWD
    beq @pwd
    cmp #NBOX_APPLET_CD
    beq @cd
    cmp #NBOX_APPLET_LS
    beq @ls
    cmp #NBOX_APPLET_CAT
    beq @cat
    cmp #NBOX_APPLET_RM
    beq @rm
    cmp #NBOX_APPLET_MV
    beq @mv
    cmp #NBOX_APPLET_MKDIR
    beq @mkdir
    cmp #NBOX_APPLET_RMDIR
    beq @rmdir
    cmp #NBOX_APPLET_CP
    beq @cp
    cmp #NBOX_APPLET_PS
    beq @ps

    jsr nbox_print_unknown
    lda #EINVAL
    jmp sys_exit

@help:
    jsr nbox_help
    bra @ok

@pwd:
    jsr nbox_pwd
    bra @ok

@cd:
    jsr nbox_cd
    bra @ok

@ls:
    jsr nbox_ls
    bra @ok

@cat:
    jsr nbox_cat
    bra @ok

@rm:
    jsr nbox_rm
    bra @ok

@mv:
    jsr nbox_mv
    bra @ok

@mkdir:
    jsr nbox_mkdir
    bra @ok

@rmdir:
    jsr nbox_rmdir
    bra @ok

@cp:
    jsr nbox_cp
    bra @ok

@ps:
    jsr nbox_ps

@ok:
    lda #EXIT_OK
    jmp sys_exit
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
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF

nbox_cmd_launch_ids:
    .byte NBOX_APPLET_HELP
    .byte NBOX_APPLET_PWD
    .byte NBOX_APPLET_CD
    .byte NBOX_APPLET_LS
    .byte NBOX_APPLET_CAT
    .byte NBOX_APPLET_RM
    .byte NBOX_APPLET_MV
    .byte NBOX_APPLET_MKDIR
    .byte NBOX_APPLET_RMDIR
    .byte NBOX_APPLET_CP
    .byte NBOX_APPLET_PS

nbox_cmd_exec_modes:
    .byte NBOX_EXEC_CHILD       ; HELP
    .byte NBOX_EXEC_CHILD       ; PWD
    .byte NBOX_EXEC_PARENT      ; CD changes parent/shell cwd
    .byte NBOX_EXEC_CHILD       ; LS
    .byte NBOX_EXEC_CHILD       ; CAT
    .byte NBOX_EXEC_CHILD       ; RM
    .byte NBOX_EXEC_CHILD       ; MV
    .byte NBOX_EXEC_CHILD       ; MKDIR
    .byte NBOX_EXEC_CHILD       ; RMDIR
    .byte NBOX_EXEC_CHILD       ; CP
    .byte NBOX_EXEC_CHILD       ; PS

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
