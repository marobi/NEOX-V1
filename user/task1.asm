; ============================================================
; task1.asm
; NEOX - pipe smoke regression test
; ca65 / W65C02
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task1_entry

.segment "USER_DATA"

pipe_read_fd:       .res 1
pipe_write_fd:      .res 1
pipe_buf:           .res 4

pipe_msg:           .byte "ABC"

msg_start:          .byte "T1 PIPE SMOKE", 13
msg_pipe_ok:        .byte "pipe ok", 13
msg_write_ok:       .byte "write ok", 13
msg_read_ok:        .byte "read ok", 13
msg_close_ok:       .byte "close ok", 13
msg_pass:           .byte "PIPE PASS", 13
msg_fail:           .byte "PIPE FAIL", 13

wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

pipe_write_args:
    .byte 0
    .byte 0
    .word pipe_msg
    .word 3

pipe_read_args:
    .byte 0
    .byte 0
    .word pipe_buf
    .word 3

close_args:
    .byte 0
    .byte 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; print_msg
;
; Input:
;   A/X = string pointer
;   Y   = length including CR
; ------------------------------------------------------------

.proc print_msg
    sta wr_stdout_args + rw_args::buf_ptr
    stx wr_stdout_args + rw_args::buf_ptr + 1

    tya
    sta wr_stdout_args + rw_args::len
    stz wr_stdout_args + rw_args::len + 1

    ldx #<wr_stdout_args
    ldy #>wr_stdout_args
    jsr sys_write
    rts
.endproc

.proc print_start
    lda #<msg_start
    ldx #>msg_start
    ldy #14
    jmp print_msg
.endproc

.proc print_pipe_ok
    lda #<msg_pipe_ok
    ldx #>msg_pipe_ok
    ldy #8
    jmp print_msg
.endproc

.proc print_write_ok
    lda #<msg_write_ok
    ldx #>msg_write_ok
    ldy #9
    jmp print_msg
.endproc

.proc print_read_ok
    lda #<msg_read_ok
    ldx #>msg_read_ok
    ldy #8
    jmp print_msg
.endproc

.proc print_close_ok
    lda #<msg_close_ok
    ldx #>msg_close_ok
    ldy #9
    jmp print_msg
.endproc

.proc print_pass
    lda #<msg_pass
    ldx #>msg_pass
    ldy #10
    jmp print_msg
.endproc

.proc print_fail
    lda #<msg_fail
    ldx #>msg_fail
    ldy #10
    jmp print_msg
.endproc

; ------------------------------------------------------------
; close_fd
;
; Input:
;   A = fd
; ------------------------------------------------------------

.proc close_fd
    sta close_args

    ldx #<close_args
    ldy #>close_args
    jsr sys_close
    rts
.endproc

; ------------------------------------------------------------
; user_task1_entry
; ------------------------------------------------------------

.proc user_task1_entry
    jsr print_start

    ; --------------------------------------------------------
    ; pipe()
    ; --------------------------------------------------------

    jsr sys_pipe
    bcc :+
    jmp @fail
:
    sta pipe_read_fd
    stx pipe_write_fd

    jsr print_pipe_ok

    ; --------------------------------------------------------
    ; write(write_fd, "ABC", 3)
    ; --------------------------------------------------------

    lda pipe_write_fd
    sta pipe_write_args + rw_args::fd

    ldx #<pipe_write_args
    ldy #>pipe_write_args
    jsr sys_write
    bcc :+
    jmp @fail
:
    cmp #3
    beq :+
    jmp @fail
:
    cpx #0
    beq :+
    jmp @fail
:
    jsr print_write_ok

    ; --------------------------------------------------------
    ; read(read_fd, pipe_buf, 3)
    ; --------------------------------------------------------

    lda pipe_read_fd
    sta pipe_read_args + rw_args::fd

    ldx #<pipe_read_args
    ldy #>pipe_read_args
    jsr sys_read
    bcc :+
    jmp @fail
:
    cmp #3
    beq :+
    jmp @fail
:
    cpx #0
    beq :+
    jmp @fail
:
    lda pipe_buf
    cmp #'A'
    beq :+
    jmp @fail
:
    lda pipe_buf+1
    cmp #'B'
    beq :+
    jmp @fail
:
    lda pipe_buf+2
    cmp #'C'
    beq :+
    jmp @fail
:
    jsr print_read_ok

    ; --------------------------------------------------------
    ; close both ends
    ; --------------------------------------------------------

    lda pipe_read_fd
    jsr close_fd
    bcc :+
    jmp @fail
:
    lda pipe_write_fd
    jsr close_fd
    bcc :+
    jmp @fail
:
    jsr print_close_ok
    jsr print_pass
    bra @idle

@fail:
    jsr print_fail

@idle:
    lda #100
    jsr sys_sleep
    bra @idle
.endproc
