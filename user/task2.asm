; ============================================================
; task2.asm
; NEOX - inter-process pipe ping/pong responder
; ca65 / W65C02
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task2_entry

T2_RX_FD = 3          ; Task 1 -> Task 2
T2_TX_FD = 4          ; Task 2 -> Task 1

.segment "USER_DATA"

t2_pong_byte:
    .byte "Q"

t2_rx_byte:
    .res 1

t2_msg_start:
    .byte "T2 PINGPONG START", 13

; Failure message layout:
;   "T2 PINGPONG FAIL " + one diagnostic code + CR
;
; Codes:
;   R = sys_read returned real error
;   A = sys_read returned low byte count != 1
;   X = sys_read returned high byte count != 0
;   B = sys_read returned byte other than 'P'
;   W = sys_write returned real error
;   C = sys_write returned low byte count != 1
;   H = sys_write returned high byte count != 0

t2_msg_fail:
    .byte "T2 PINGPONG FAIL "

t2_fail_code:
    .byte "?"

    .byte 13

t2_wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t2_read_args:
    .byte T2_RX_FD
    .byte 0
    .word t2_rx_byte
    .word 1

t2_write_args:
    .byte T2_TX_FD
    .byte 0
    .word t2_pong_byte
    .word 1

.segment "USER_TEXT"

; ------------------------------------------------------------
; t2_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = length including CR
; ------------------------------------------------------------

.proc t2_print_msg
    sta t2_wr_stdout_args + rw_args::buf_ptr
    stx t2_wr_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t2_wr_stdout_args + rw_args::len
    stz t2_wr_stdout_args + rw_args::len + 1

    SYSCALL t2_wr_stdout_args, sys_write
    rts
.endproc

.proc t2_print_start
    lda #<t2_msg_start
    ldx #>t2_msg_start
    ldy #18
    jmp t2_print_msg
.endproc

.proc t2_print_fail
    lda #<t2_msg_fail
    ldx #>t2_msg_fail
    ldy #19
    jmp t2_print_msg
.endproc

; ------------------------------------------------------------
; t2_read_ping
;
; Blocking pipe read. The kernel handles EAGAIN by blocking
; and retrying the syscall; task code only handles EOF/real errors.
; ------------------------------------------------------------

.proc t2_read_ping
    SYSCALL t2_read_args, sys_read
    bcc @ok

    lda #'R'                ; read returned real error
    sta t2_fail_code
    sec
    rts

@ok:
    cmp #1
    beq :+
    lda #'A'                ; read low byte count was not 1
    sta t2_fail_code
    sec
    rts
:
    cpx #0
    beq :+
    lda #'X'                ; read high byte count was not 0
    sta t2_fail_code
    sec
    rts
:
    lda t2_rx_byte
    cmp #'P'
    beq :+
    lda #'B'                ; read byte was not 'P'
    sta t2_fail_code
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; t2_write_pong
;
; Blocking pipe write. The kernel handles EAGAIN by blocking
; and retrying the syscall; task code only handles real errors.
; ------------------------------------------------------------

.proc t2_write_pong
    SYSCALL t2_write_args, sys_write
    bcc @ok

    lda #'W'                ; write returned real error
    sta t2_fail_code
    sec
    rts

@ok:
    cmp #1
    beq :+
    lda #'C'                ; write low byte count was not 1
    sta t2_fail_code
    sec
    rts
:
    cpx #0
    beq :+
    lda #'H'                ; write high byte count was not 0
    sta t2_fail_code
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; user_task2_entry
; ------------------------------------------------------------

.proc user_task2_entry
    jsr t2_print_start

@loop:
    jsr t2_read_ping
    bcc :+
    jmp @fail
:
    jsr t2_write_pong
    bcc :+
    jmp @fail
:
	lda #$01
	jsr sys_sleep
    bra @loop

@fail:
    jsr t2_print_fail

@idle:
    ; Failure stop loop.
	lda #$10
	jsr sys_sleep
    bra @idle
.endproc
