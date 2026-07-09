; ============================================================
; neosh.asm
; NEOX - interactive shell loop
;
; Purpose:
;   Interactive shell front-end for task 6.  It owns the prompt,
;   VDU line input, prompt-prefix stripping, and dispatch to nbox.
;
; Commands are implemented in user/nbox.asm.
;
; Input policy:
;   - RP VDU owns line editing and echo
;   - neosh reads one complete edited line with SYS_READ
;   - if the returned line starts with the prompt neosh printed, neosh strips
;     that prompt before calling nbox
;   - nbox receives only a clean command line
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

neosh_prompt_tail:
    .byte "> "

neosh_cr:
    .byte 13

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

neosh_spawn_alloc_args:
    .word nbox_child_entry
    .byte SPAWN_FLAGS_NONE
    .byte $FF

neosh_spawn_set_launch_args:
    .byte $FF
    .byte NBOX_APPLET_NONE

neosh_spawn_set_args2_args:
    .byte $FF
    .byte 0
    .word nbox_arg_buf
    .byte 0
    .word nbox_arg2_buf
    .byte 0

neosh_spawn_child_args:
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
; neosh_abort_spawn_child
;
; Abort the pending child recorded in neosh_spawn_child_pid.  Used only
; on setup failures before spawn_commit has made the child runnable.
; ------------------------------------------------------------
.proc neosh_abort_spawn_child
    lda neosh_spawn_child_pid
    sta neosh_spawn_child_args + spawn_child_args::child_pid
    SYSCALL neosh_spawn_child_args, sys_spawn_abort
    rts
.endproc

; ------------------------------------------------------------
; neosh_spawn_resolved_child
;
; Spawn the already-resolved nbox command as a resident child, using
; the launch id and up to two copied arguments.  Normal stdin/stdout/
; stderr inheritance is handled by SYS_SPAWN_ALLOC_RESIDENT.
;
; Return:
;   C clear = child completed and was reaped
;   C set   = spawn/setup/commit/wait failed
; ------------------------------------------------------------
.proc neosh_spawn_resolved_child
    jsr neosh_prepare_spawn_args

    SYSCALL neosh_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated
    sec
    rts

@allocated:
    sta neosh_spawn_child_pid

    sta neosh_spawn_set_launch_args + spawn_set_launch_id_args::child_pid
    lda nbox_launch_id
    sta neosh_spawn_set_launch_args + spawn_set_launch_id_args::launch_id

    SYSCALL neosh_spawn_set_launch_args, sys_spawn_set_launch_id
    bcc @launch_ok
    jsr neosh_abort_spawn_child
    sec
    rts

@launch_ok:
    lda neosh_spawn_child_pid
    sta neosh_spawn_set_args2_args + spawn_set_args2_args::child_pid

    lda neosh_spawn_argc
    sta neosh_spawn_set_args2_args + spawn_set_args2_args::argc

    lda nbox_arg_len
    sta neosh_spawn_set_args2_args + spawn_set_args2_args::arg0_len

    lda nbox_arg2_len
    sta neosh_spawn_set_args2_args + spawn_set_args2_args::arg1_len

    SYSCALL neosh_spawn_set_args2_args, sys_spawn_set_args2
    bcc @args_ok
    jsr neosh_abort_spawn_child
    sec
    rts

@args_ok:
    lda neosh_spawn_child_pid
    sta neosh_spawn_child_args + spawn_child_args::child_pid

    SYSCALL neosh_spawn_child_args, sys_spawn_commit
    bcc @commit_ok
    jsr neosh_abort_spawn_child
    sec
    rts

@commit_ok:
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
    jsr nbox_dispatch_line
    clc
    rts

@child:
    jsr neosh_spawn_resolved_child
    bcc @done
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
    jsr neosh_execute_clean_line
    bra @prompt
.endproc
