; ============================================================
; task3.asm
; NEOX Phase 3 anonymous-pipe validation
;
; PID 3 is not part of the static PID 1/PID 2 pipe wiring.
; It therefore has free descriptors for sys_pipe.
;
; Tests:
;   - anonymous sys_pipe creation
;   - local write/read
;   - final writer close
;   - EOF after buffered data is drained
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export phase3_pipe_task3_entry

T3_FD_NONE = $FF

.segment "USER_DATA"

t3_read_fd:
    .byte T3_FD_NONE

t3_write_fd:
    .byte T3_FD_NONE

t3_data:
    .byte "XYZ"

t3_buffer:
    .res 3

t3_byte:
    .res 1

t3_msg_start:
    .byte "P3 PIPE T3 START", 13
T3_MSG_START_LEN = * - t3_msg_start

t3_msg_pass:
    .byte "P3 PIPE T3 PASS", 13
T3_MSG_PASS_LEN = * - t3_msg_pass

t3_msg_fail:
    .byte "P3 PIPE T3 FAIL "

t3_fail_code:
    .byte "?"

    .byte 13
T3_MSG_FAIL_LEN = * - t3_msg_fail

t3_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t3_rw_args:
    .byte 0
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc t3_print
    sta t3_stdout_args + rw_args::buf_ptr
    stx t3_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t3_stdout_args + rw_args::len
    stz t3_stdout_args + rw_args::len + 1

    SYSCALL t3_stdout_args, sys_write
    rts
.endproc

; ------------------------------------------------------------
.proc t3_print_start
    lda #<t3_msg_start
    ldx #>t3_msg_start
    ldy #T3_MSG_START_LEN
    jmp t3_print
.endproc

; ------------------------------------------------------------
.proc t3_stop_pass
    lda #<t3_msg_pass
    ldx #>t3_msg_pass
    ldy #T3_MSG_PASS_LEN
    jsr t3_print

@idle:
    lda #$20
    jsr sys_sleep
    bra @idle
.endproc

; ------------------------------------------------------------
; Input:
;   A = diagnostic code
; ------------------------------------------------------------
.proc t3_stop_fail
    sta t3_fail_code

    lda #<t3_msg_fail
    ldx #>t3_msg_fail
    ldy #T3_MSG_FAIL_LEN
    jsr t3_print

@idle:
    lda #$20
    jsr sys_sleep
    bra @idle
.endproc

; ------------------------------------------------------------
; Input:
;   A/X = buffer
;   Y   = length low
; ------------------------------------------------------------
.proc t3_set_rw_buffer
    sta t3_rw_args + rw_args::buf_ptr
    stx t3_rw_args + rw_args::buf_ptr + 1

    tya
    sta t3_rw_args + rw_args::len
    stz t3_rw_args + rw_args::len + 1
    rts
.endproc

; ------------------------------------------------------------
.proc phase3_pipe_task3_entry
    jsr t3_print_start

    jsr sys_pipe
    bcc @pipe_ok

    lda #'P'
    jmp t3_stop_fail

@pipe_ok:
    sta t3_read_fd
    stx t3_write_fd

    ; Write XYZ.
    stx t3_rw_args + rw_args::fd

    lda #<t3_data
    ldx #>t3_data
    ldy #3
    jsr t3_set_rw_buffer

    SYSCALL t3_rw_args, sys_write
    bcc @write_ok

    lda #'W'
    jmp t3_stop_fail

@write_ok:
    cmp #3
    beq :+
    lda #'w'
    jmp t3_stop_fail
:
    cpx #0
    beq :+
    lda #'w'
    jmp t3_stop_fail
:

    ; Read XYZ.
    lda t3_read_fd
    sta t3_rw_args + rw_args::fd

    lda #<t3_buffer
    ldx #>t3_buffer
    ldy #3
    jsr t3_set_rw_buffer

    SYSCALL t3_rw_args, sys_read
    bcc @read_ok

    lda #'R'
    jmp t3_stop_fail

@read_ok:
    cmp #3
    beq :+
    lda #'r'
    jmp t3_stop_fail
:
    cpx #0
    beq :+
    lda #'r'
    jmp t3_stop_fail
:

    ldy #0
@verify:
    lda t3_buffer,y
    cmp t3_data,y
    beq :+
    lda #'V'
    jmp t3_stop_fail
:
    iny
    cpy #3
    bne @verify

    ; Final writer close.
    lda t3_write_fd
    jsr sys_close
    bcc @writer_closed

    lda #'C'
    jmp t3_stop_fail

@writer_closed:
    lda #T3_FD_NONE
    sta t3_write_fd

    ; Empty read after final writer close must return EOF.
    lda t3_read_fd
    sta t3_rw_args + rw_args::fd

    lda #<t3_byte
    ldx #>t3_byte
    ldy #1
    jsr t3_set_rw_buffer

    SYSCALL t3_rw_args, sys_read
    bcc @eof_returned

    lda #'F'
    jmp t3_stop_fail

@eof_returned:
    cmp #0
    beq :+
    lda #'E'
    jmp t3_stop_fail
:
    cpx #0
    beq :+
    lda #'E'
    jmp t3_stop_fail
:

    lda t3_read_fd
    jsr sys_close
    bcc :+

    lda #'D'
    jmp t3_stop_fail
:
    jmp t3_stop_pass
.endproc
