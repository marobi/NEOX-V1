; ============================================================
; task2.asm
; NEOX Phase 3 pipe validation peer
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export phase3_pipe_task2_entry

T2_STATIC_RX_FD = 3
T2_STATIC_TX_FD = 4
T2_FD_NONE      = $FF

.segment "USER_DATA"

t2_rx_fd:
    .byte T2_FD_NONE

t2_tx_fd:
    .byte T2_FD_NONE

t2_buffer:
    .res 65

t2_ack:
    .res 1

t2_drain:
    .byte "DRAIN"

t2_msg_start:
    .byte "P3 PIPE T2 START", 13
T2_MSG_START_LEN = * - t2_msg_start

t2_msg_pass:
    .byte "P3 PIPE T2 PASS", 13
T2_MSG_PASS_LEN = * - t2_msg_pass

t2_msg_fail:
    .byte "P3 PIPE T2 FAIL "

t2_fail_code:
    .byte "?"

    .byte 13
T2_MSG_FAIL_LEN = * - t2_msg_fail

t2_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t2_rw_args:
    .byte 0
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
.proc t2_print
    sta t2_stdout_args + rw_args::buf_ptr
    stx t2_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t2_stdout_args + rw_args::len
    stz t2_stdout_args + rw_args::len + 1

    SYSCALL t2_stdout_args, sys_write
    rts
.endproc

; ------------------------------------------------------------
.proc t2_print_start
    lda #<t2_msg_start
    ldx #>t2_msg_start
    ldy #T2_MSG_START_LEN
    jmp t2_print
.endproc

; ------------------------------------------------------------
.proc t2_stop_pass
    lda #<t2_msg_pass
    ldx #>t2_msg_pass
    ldy #T2_MSG_PASS_LEN
    jsr t2_print

@idle:
    lda #$20
    jsr sys_sleep
    bra @idle
.endproc

; ------------------------------------------------------------
; Input:
;   A = diagnostic code
; ------------------------------------------------------------
.proc t2_stop_fail
    sta t2_fail_code

    lda #<t2_msg_fail
    ldx #>t2_msg_fail
    ldy #T2_MSG_FAIL_LEN
    jsr t2_print

@idle:
    lda #$20
    jsr sys_sleep
    bra @idle
.endproc

; ------------------------------------------------------------
.proc t2_set_rw_buffer
    sta t2_rw_args + rw_args::buf_ptr
    stx t2_rw_args + rw_args::buf_ptr + 1

    tya
    sta t2_rw_args + rw_args::len
    stz t2_rw_args + rw_args::len + 1
    rts
.endproc

; ------------------------------------------------------------
.proc t2_dup_static_endpoints
    lda #T2_STATIC_RX_FD
    jsr sys_dup
    bcc @rx_dup_ok

    lda #'1'
    sec
    rts

@rx_dup_ok:
    sta t2_rx_fd

    lda #T2_STATIC_RX_FD
    jsr sys_close
    bcc @rx_close_ok

    lda #'2'
    sec
    rts

@rx_close_ok:
    lda #T2_STATIC_TX_FD
    jsr sys_dup
    bcc @tx_dup_ok

    lda #'3'
    sec
    rts

@tx_dup_ok:
    sta t2_tx_fd

    lda #T2_STATIC_TX_FD
    jsr sys_close
    bcc @tx_close_ok

    lda #'4'
    sec
    rts

@tx_close_ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; Input:
;   A = byte to send
; ------------------------------------------------------------
.proc t2_send_ack
    sta t2_ack

    lda t2_tx_fd
    sta t2_rw_args + rw_args::fd

    lda #<t2_ack
    ldx #>t2_ack
    ldy #1
    jsr t2_set_rw_buffer

    SYSCALL t2_rw_args, sys_write
    bcc @ok

    lda #'A'
    sec
    rts

@ok:
    cmp #1
    bne @bad_count
    cpx #0
    bne @bad_count

    clc
    rts

@bad_count:
    lda #'a'
    sec
    rts
.endproc

; ------------------------------------------------------------
.proc phase3_pipe_task2_entry
    jsr t2_print_start

    jsr t2_dup_static_endpoints
    bcc :+
    jmp t2_stop_fail
:

    ; Read bytes 0..31 from the initial 64-byte short write.
    lda t2_rx_fd
    sta t2_rw_args + rw_args::fd

    lda #<t2_buffer
    ldx #>t2_buffer
    ldy #32
    jsr t2_set_rw_buffer

    SYSCALL t2_rw_args, sys_read
    bcc :+
    lda #'R'
    jmp t2_stop_fail
:
    cmp #32
    beq :+
    jmp @first_count_fail
:
    cpx #0
    beq :+
    jmp @first_count_fail
:

    ldy #0
@verify_first:
    tya
    cmp t2_buffer,y
    beq :+
    jmp @first_data_fail
:

    iny
    cpy #32
    bne @verify_first

    lda #'A'
    jsr t2_send_ack
    bcc :+
    jmp t2_stop_fail
:

    ; Allow Task 1 to add bytes 64..95.
    lda #5
    jsr sys_sleep

    ; Remaining logical sequence is 32..95 and crosses the ring end.
    lda t2_rx_fd
    sta t2_rw_args + rw_args::fd

    lda #<t2_buffer
    ldx #>t2_buffer
    ldy #65
    jsr t2_set_rw_buffer

    SYSCALL t2_rw_args, sys_read
    bcc :+
    lda #'S'
    jmp t2_stop_fail
:
    cmp #64
    beq :+
    jmp @second_count_fail
:
    cpx #0
    beq :+
    jmp @second_count_fail
:

    ldy #0
@verify_second:
    tya
    clc
    adc #32
    cmp t2_buffer,y
    beq :+
    jmp @second_data_fail
:

    iny
    cpy #64
    bne @verify_second

    lda #'B'
    jsr t2_send_ack
    bcc :+
    jmp t2_stop_fail
:

    ; Task 1 now fills the pipe and blocks on one extra byte.
    lda #20
    jsr sys_sleep

    ; Final read-end close must wake the blocked writer for EPIPE.
    lda t2_rx_fd
    jsr sys_close
    bcc :+
    lda #'C'
    jmp t2_stop_fail
:
    lda #T2_FD_NONE
    sta t2_rx_fd

    ; Leave buffered data for Task 1, then close the final writer.
    lda t2_tx_fd
    sta t2_rw_args + rw_args::fd

    lda #<t2_drain
    ldx #>t2_drain
    ldy #5
    jsr t2_set_rw_buffer

    SYSCALL t2_rw_args, sys_write
    bcc :+
    lda #'W'
    jmp t2_stop_fail
:
    cmp #5
    beq :+
    jmp @drain_count_fail
:
    cpx #0
    beq :+
    jmp @drain_count_fail
:

    lda t2_tx_fd
    jsr sys_close
    bcc :+
    lda #'D'
    jmp t2_stop_fail
:
    lda #T2_FD_NONE
    sta t2_tx_fd

    jmp t2_stop_pass

@first_count_fail:
    lda #'5'
    jmp t2_stop_fail

@first_data_fail:
    lda #'6'
    jmp t2_stop_fail

@second_count_fail:
    lda #'7'
    jmp t2_stop_fail

@second_data_fail:
    lda #'8'
    jmp t2_stop_fail

@drain_count_fail:
    lda #'9'
    jmp t2_stop_fail
.endproc
