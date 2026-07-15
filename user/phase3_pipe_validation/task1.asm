; ============================================================
; task1.asm
; NEOX Phase 3 pipe validation coordinator
;
; Tests:
;   - dup-backed endpoint lifetime
;   - zero-length read/write
;   - 65-byte write returning a 64-byte short write
;   - ring wrap across offset 63 -> 0
;   - blocked full-pipe writer
;   - final reader close wake-up
;   - EPIPE after the final reader closes
;   - buffered drain after final writer close
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export phase3_pipe_task1_entry

T1_STATIC_TX_FD = 3
T1_STATIC_RX_FD = 4
T1_FD_NONE      = $FF

.segment "USER_DATA"

t1_tx_fd:
    .byte T1_FD_NONE

t1_rx_fd:
    .byte T1_FD_NONE

t1_local_read_fd:
    .byte T1_FD_NONE

t1_local_write_fd:
    .byte T1_FD_NONE

t1_byte:
    .res 1

t1_buffer:
    .res 96

t1_local_data:
    .byte "XYZ"

t1_expected_drain:
    .byte "DRAIN"

t1_msg_start:
    .byte "P3 PIPE T1 START", 13
T1_MSG_START_LEN = * - t1_msg_start

t1_msg_pass:
    .byte "P3 PIPE T1 PASS", 13
T1_MSG_PASS_LEN = * - t1_msg_pass

t1_msg_fail:
    .byte "P3 PIPE T1 FAIL "

t1_fail_code:
    .byte "?"

    .byte 13
T1_MSG_FAIL_LEN = * - t1_msg_fail

t1_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t1_rw_args:
    .byte 0
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc t1_print
    sta t1_stdout_args + rw_args::buf_ptr
    stx t1_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t1_stdout_args + rw_args::len
    stz t1_stdout_args + rw_args::len + 1

    SYSCALL t1_stdout_args, sys_write
    rts
.endproc

; ------------------------------------------------------------
.proc t1_print_start
    lda #<t1_msg_start
    ldx #>t1_msg_start
    ldy #T1_MSG_START_LEN
    jmp t1_print
.endproc

; ------------------------------------------------------------
.proc t1_print_pass
    lda #<t1_msg_pass
    ldx #>t1_msg_pass
    ldy #T1_MSG_PASS_LEN
    jmp t1_print
.endproc

; ------------------------------------------------------------
; Input:
;   A = diagnostic code
; ------------------------------------------------------------
.proc t1_stop_fail
    sta t1_fail_code

    lda #<t1_msg_fail
    ldx #>t1_msg_fail
    ldy #T1_MSG_FAIL_LEN
    jsr t1_print

@idle:
    lda #$20
    jsr sys_sleep
    bra @idle
.endproc

; ------------------------------------------------------------
.proc t1_stop_pass
    jsr t1_print_pass

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
.proc t1_set_rw_buffer
    sta t1_rw_args + rw_args::buf_ptr
    stx t1_rw_args + rw_args::buf_ptr + 1

    tya
    sta t1_rw_args + rw_args::len
    stz t1_rw_args + rw_args::len + 1
    rts
.endproc

; ------------------------------------------------------------
; Return:
;   C clear = local anonymous-pipe test passed
;   C set   = failed, A = code
; ------------------------------------------------------------
.proc t1_test_local_pipe
    jsr sys_pipe
    bcc @pipe_ok

    lda #'P'
    sec
    rts

@pipe_ok:
    sta t1_local_read_fd
    stx t1_local_write_fd

    ; Write XYZ.
    stx t1_rw_args + rw_args::fd

    lda #<t1_local_data
    ldx #>t1_local_data
    ldy #3
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_write
    bcc @write_ok

    lda #'W'
    sec
    rts

@write_ok:
    cmp #3
    beq :+
    jmp @bad_write_count
:
    cpx #0
    beq :+
    jmp @bad_write_count
:

    ; Read XYZ.
    lda t1_local_read_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #3
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_read
    bcc @read_ok

    lda #'R'
    sec
    rts

@read_ok:
    cmp #3
    bne @bad_read_count

    cpx #0
    bne @bad_read_count

    ldy #0
@verify_local:
    lda t1_buffer,y
    cmp t1_local_data,y
    bne @bad_local_data

    iny
    cpy #3
    bne @verify_local

    ; Final writer close.
    lda t1_local_write_fd
    jsr sys_close
    bcc @writer_closed

    lda #'C'
    sec
    rts

@writer_closed:
    lda #T1_FD_NONE
    sta t1_local_write_fd

    ; Empty read after final writer close must be EOF.
    lda t1_local_read_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_byte
    ldx #>t1_byte
    ldy #1
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_read
    bcc @eof_ok

    lda #'F'
    sec
    rts

@eof_ok:
    cmp #0
    bne @bad_eof

    cpx #0
    bne @bad_eof

    lda t1_local_read_fd
    jsr sys_close
    bcc @done

    lda #'D'
    sec
    rts

@done:
    lda #T1_FD_NONE
    sta t1_local_read_fd
    clc
    rts

@bad_write_count:
    lda #'w'
    sec
    rts

@bad_read_count:
    lda #'r'
    sec
    rts

@bad_local_data:
    lda #'V'
    sec
    rts

@bad_eof:
    lda #'E'
    sec
    rts
.endproc

; ------------------------------------------------------------
; Replace both static descriptors with dup-backed descriptors.
;
; Allocation sequence with fd 0..4 occupied:
;   dup(3) -> 5, close(3)
;   dup(4) -> 3, close(4)
; ------------------------------------------------------------
.proc t1_dup_static_endpoints
    lda #T1_STATIC_TX_FD
    jsr sys_dup
    bcc @tx_dup_ok

    lda #'1'
    sec
    rts

@tx_dup_ok:
    sta t1_tx_fd

    lda #T1_STATIC_TX_FD
    jsr sys_close
    bcc @tx_close_ok

    lda #'2'
    sec
    rts

@tx_close_ok:
    lda #T1_STATIC_RX_FD
    jsr sys_dup
    bcc @rx_dup_ok

    lda #'3'
    sec
    rts

@rx_dup_ok:
    sta t1_rx_fd

    lda #T1_STATIC_RX_FD
    jsr sys_close
    bcc @rx_close_ok

    lda #'4'
    sec
    rts

@rx_close_ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
.proc t1_fill_pattern
    ldy #0
@loop:
    tya
    sta t1_buffer,y

    iny
    cpy #96
    bne @loop
    rts
.endproc

; ------------------------------------------------------------
; Input:
;   A = expected acknowledgement byte
;
; Return:
;   C clear = received
;   C set   = failure, A = diagnostic code
; ------------------------------------------------------------
.proc t1_read_ack
    pha

    lda t1_rx_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_byte
    ldx #>t1_byte
    ldy #1
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_read
    bcc @read_ok

    pla
    lda #'A'
    sec
    rts

@read_ok:
    cmp #1
    bne @bad_count

    cpx #0
    bne @bad_count

    pla
    cmp t1_byte
    beq @ok

    lda #'B'
    sec
    rts

@bad_count:
    pla
    lda #'a'
    sec
    rts

@ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
.proc phase3_pipe_task1_entry
    jsr t1_print_start

    jsr t1_dup_static_endpoints
    bcc :+
    jmp t1_stop_fail
:

    ; Zero-length write.
    lda t1_tx_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #0
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_write
    bcc :+
    lda #'Z'
    jmp t1_stop_fail
:
    cmp #0
    beq :+
    jmp @zero_fail
:
    cpx #0
    beq :+
    jmp @zero_fail
:

    ; Zero-length read.
    lda t1_rx_fd
    sta t1_rw_args + rw_args::fd

    SYSCALL t1_rw_args, sys_read
    bcc :+
    lda #'Y'
    jmp t1_stop_fail
:
    cmp #0
    beq :+
    jmp @zero_fail
:
    cpx #0
    beq :+
    jmp @zero_fail
:
    jsr t1_fill_pattern

    ; Write 65 bytes to an empty 64-byte pipe. Expected short write: 64.
    lda t1_tx_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #65
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_write
    bcc :+
    lda #'S'
    jmp t1_stop_fail
:
    cmp #64
    beq :+
    jmp @short_fail
:
    cpx #0
    beq :+
    jmp @short_fail
:

    ; Task 2 consumed bytes 0..31.
    lda #'A'
    jsr t1_read_ack
    bcc :+
    jmp t1_stop_fail
:

    ; Add bytes 64..95 into the 32 free slots. The head wraps.
    lda t1_tx_fd
    sta t1_rw_args + rw_args::fd

    lda #<(t1_buffer + 64)
    ldx #>(t1_buffer + 64)
    ldy #32
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_write
    bcc :+
    lda #'T'
    jmp t1_stop_fail
:
    cmp #32
    beq :+
    jmp @wrap_write_fail
:
    cpx #0
    beq :+
    jmp @wrap_write_fail
:

    ; Task 2 verified bytes 32..95.
    lda #'B'
    jsr t1_read_ack
    bcc :+
    jmp t1_stop_fail
:

    ; Fill the pipe, then block on one extra byte.
    lda t1_tx_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #64
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_write
    bcc :+
    lda #'U'
    jmp t1_stop_fail
:
    cmp #64
    beq :+
    jmp @full_write_fail
:
    cpx #0
    beq :+
    jmp @full_write_fail
:

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #1
    jsr t1_set_rw_buffer

    ; Task 2 closes the final reader while this call is blocked.
    SYSCALL t1_rw_args, sys_write
    bcs @write_failed

    lda #'N'
    jmp t1_stop_fail

@write_failed:
    cpy #EPIPE
    beq @epipe_ok

    lda #'E'
    jmp t1_stop_fail

@epipe_ok:
    ; Task 2 writes DRAIN and closes the final writer.
    lda t1_rx_fd
    sta t1_rw_args + rw_args::fd

    lda #<t1_buffer
    ldx #>t1_buffer
    ldy #64
    jsr t1_set_rw_buffer

    SYSCALL t1_rw_args, sys_read
    bcc :+
    lda #'G'
    jmp t1_stop_fail
:
    cmp #5
    beq :+
    jmp @drain_count_fail
:
    cpx #0
    beq :+
    jmp @drain_count_fail
:

    ldy #0
@verify_drain:
    lda t1_buffer,y
    cmp t1_expected_drain,y
    beq :+
    jmp @drain_data_fail
:

    iny
    cpy #5
    bne @verify_drain

    ; Buffer drained and no writer remains: EOF.
    SYSCALL t1_rw_args, sys_read
    bcc :+
    lda #'H'
    jmp t1_stop_fail
:
    cmp #0
    beq :+
    jmp @final_eof_fail
:
    cpx #0
    beq :+
    jmp @final_eof_fail
:

    lda t1_rx_fd
    jsr sys_close
    bcc :+
    lda #'I'
    jmp t1_stop_fail
:
    jmp t1_stop_pass

@zero_fail:
    lda #'0'
    jmp t1_stop_fail

@short_fail:
    lda #'5'
    jmp t1_stop_fail

@wrap_write_fail:
    lda #'6'
    jmp t1_stop_fail

@full_write_fail:
    lda #'7'
    jmp t1_stop_fail

@drain_count_fail:
    lda #'8'
    jmp t1_stop_fail

@drain_data_fail:
    lda #'9'
    jmp t1_stop_fail

@final_eof_fail:
    lda #'O'
    jmp t1_stop_fail
.endproc
