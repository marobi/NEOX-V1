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

.export neosh_main

.import nbox_line_buf
.import nbox_line_len
.import nbox_dispatch_line

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

.proc neosh_main
@prompt:
    jsr neosh_print_prompt

@loop:
    jsr neosh_read_line
    bcs @loop

    jsr neosh_copy_clean_line_to_nbox
    jsr nbox_dispatch_line
    bra @prompt
.endproc
