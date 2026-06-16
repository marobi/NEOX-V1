; ============================================================
; task1.asm
; NEOX - inter-process pipe ping/pong initiator with sys_ticks
; ca65 / W65C02
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task1_entry

T1_TX_FD          = 3          ; Task 1 -> Task 2
T1_RX_FD          = 4          ; Task 2 -> Task 1
T1_SAMPLE_TICKS   = 200        ; TIMER 20 = 50 ms, 200 ticks = 10 sec

.segment "USER_DATA"

t1_ping_byte:
    .byte "P"

t1_rx_byte:
    .res 1

; Total completed ping-pong loops.
t1_loop_lo:
    .byte 0

t1_loop_hi:
    .byte 0

; Previous loop count sample.
t1_last_loop_lo:
    .byte 0

t1_last_loop_hi:
    .byte 0

; Tick sample start.
t1_start_tick_lo:
    .byte 0

t1_start_tick_hi:
    .byte 0

; Current sys_ticks sample.
t1_now_tick_lo:
    .byte 0

t1_now_tick_hi:
    .byte 0

; Delta loops during the last measured second.
t1_delta_loop_lo:
    .byte 0

t1_delta_loop_hi:
    .byte 0

t1_msg_start:
    .byte "T1 PINGPONG TICKS", 13

t1_msg_rate:
    .byte "T1 lps=$0000", 13
	
t1_msg_fail:
    .byte "T1 PINGPONG FAIL", 13

t1_wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t1_write_args:
    .byte T1_TX_FD
    .byte 0
    .word t1_ping_byte
    .word 1

t1_read_args:
    .byte T1_RX_FD
    .byte 0
    .word t1_rx_byte
    .word 1

.segment "USER_TEXT"

; ------------------------------------------------------------
; t1_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = length including CR
; ------------------------------------------------------------

.proc t1_print_msg
    sta t1_wr_stdout_args + rw_args::buf_ptr
    stx t1_wr_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t1_wr_stdout_args + rw_args::len
    stz t1_wr_stdout_args + rw_args::len + 1

    SYSCALL t1_wr_stdout_args, sys_write
    rts
.endproc

.proc t1_print_start
    lda #<t1_msg_start
    ldx #>t1_msg_start
    ldy #18
    jmp t1_print_msg
.endproc

.proc t1_print_fail
    lda #<t1_msg_fail
    ldx #>t1_msg_fail
    ldy #17
    jmp t1_print_msg
.endproc

; ------------------------------------------------------------
; t1_hex_nibble
;
; Input:
;   A = low nibble value
;
; Output:
;   A = ASCII hex digit
; ------------------------------------------------------------

.proc t1_hex_nibble
    and #$0F
    cmp #10
    bcc @digit

    clc
    adc #'A' - 10
    rts

@digit:
    clc
    adc #'0'
    rts
.endproc

; ------------------------------------------------------------
; t1_store_hex_byte
;
; Input:
;   A = byte
;   Y = offset in t1_msg_rate
; ------------------------------------------------------------

.proc t1_store_hex_byte
    pha

    lsr
    lsr
    lsr
    lsr
    jsr t1_hex_nibble
    sta t1_msg_rate,y

    iny
    pla
    jsr t1_hex_nibble
    sta t1_msg_rate,y

    rts
.endproc

; ------------------------------------------------------------
; t1_print_rate
;
; Prints:
;   T1 lps=$hhhh
;
; Value printed is loops completed during the last 50 ticks.
; At TIMER 50 this equals loops/sec.
; ------------------------------------------------------------

.proc t1_print_rate
    lda t1_delta_loop_hi
    ldy #8
    jsr t1_store_hex_byte

    lda t1_delta_loop_lo
    ldy #10
    jsr t1_store_hex_byte

    lda #<t1_msg_rate
    ldx #>t1_msg_rate
    ldy #13
    jmp t1_print_msg
.endproc

; ------------------------------------------------------------
; t1_sample_ticks
;
; Output:
;   t1_now_tick_lo/hi updated
; ------------------------------------------------------------

.proc t1_sample_ticks
    jsr sys_ticks
    sta t1_now_tick_lo
    stx t1_now_tick_hi
    rts
.endproc

; ------------------------------------------------------------
; t1_reset_sample
;
; Sets:
;   start_tick = sys_ticks()
;   last_loop  = current loop count
; ------------------------------------------------------------

.proc t1_reset_sample
    jsr t1_sample_ticks

    lda t1_now_tick_lo
    sta t1_start_tick_lo

    lda t1_now_tick_hi
    sta t1_start_tick_hi

    lda t1_loop_lo
    sta t1_last_loop_lo

    lda t1_loop_hi
    sta t1_last_loop_hi

    rts
.endproc

; ------------------------------------------------------------
; t1_tick_elapsed_sample
;
; Output:
;   C clear = at least T1_SAMPLE_TICKS elapsed
;   C set   = not yet elapsed
;
; Uses wrap-safe 16-bit unsigned subtraction:
;   now - start >= 500
; ------------------------------------------------------------

.proc t1_tick_elapsed_1s
    jsr t1_sample_ticks

    sec
    lda t1_now_tick_lo
    sbc t1_start_tick_lo
    tay                         ; Y = delta low

    lda t1_now_tick_hi
    sbc t1_start_tick_hi        ; A = delta high

    ; Compare delta >= 500 ($01F4)
    cmp #>T1_SAMPLE_TICKS
    bcc @not_elapsed
    bne @elapsed

    tya
    cmp #<T1_SAMPLE_TICKS
    bcc @not_elapsed

@elapsed:
    clc
    rts

@not_elapsed:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t1_update_rate
;
; If one scheduler-second elapsed:
;   delta_loop = loop_count - last_loop
;   print delta_loop
;   reset sample
;
; Called only every 16 completed loops to reduce measurement
; overhead in the hot path.
; ------------------------------------------------------------

.proc t1_update_rate
    jsr t1_tick_elapsed_1s
    bcc :+
    rts
:
    sec
    lda t1_loop_lo
    sbc t1_last_loop_lo
    sta t1_delta_loop_lo

    lda t1_loop_hi
    sbc t1_last_loop_hi
    sta t1_delta_loop_hi

    jsr t1_print_rate
    jsr t1_reset_sample
    rts
.endproc

; ------------------------------------------------------------
; t1_write_ping
;
; Blocking pipe write. The kernel handles EAGAIN by blocking
; and retrying the syscall; task code only handles real errors.
; ------------------------------------------------------------

.proc t1_write_ping
    SYSCALL t1_write_args, sys_write
    bcc @ok

    sec
    rts

@ok:
    cmp #1
    beq :+
    sec
    rts
:
    cpx #0
    beq :+
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; t1_read_pong
;
; Blocking pipe read. The kernel handles EAGAIN by blocking
; and retrying the syscall; task code only handles EOF/real errors.
; ------------------------------------------------------------

.proc t1_read_pong
    SYSCALL t1_read_args, sys_read
    bcc @ok

    sec
    rts

@ok:
    cmp #1
    beq :+
    sec
    rts
:
    cpx #0
    beq :+
    sec
    rts
:
    lda t1_rx_byte
    cmp #'Q'
    beq :+
    sec
    rts
:
    clc
    rts
.endproc

; ------------------------------------------------------------
; t1_count_loop
;
; Increment loop counter.
; Only sample ticks every 16 loops:
;   loop_lo & $0F == 0
; ------------------------------------------------------------

.proc t1_count_loop
    inc t1_loop_lo
    bne @check_sample

    inc t1_loop_hi

@check_sample:
    lda t1_loop_lo
    and #$0F
    bne @done

    jsr t1_update_rate

@done:
    rts
.endproc

; ------------------------------------------------------------
; user_task1_entry
; ------------------------------------------------------------

.proc user_task1_entry
    jsr t1_print_start

    stz t1_loop_lo
    stz t1_loop_hi
    stz t1_last_loop_lo
    stz t1_last_loop_hi
    stz t1_delta_loop_lo
    stz t1_delta_loop_hi

    jsr t1_reset_sample

@loop:
    jsr t1_write_ping
    bcc :+
    jmp @fail
:
    jsr t1_read_pong
    bcc :+
    jmp @fail
:
    jsr t1_count_loop
	
	lda #$02
	jsr sys_sleep
    bra @loop

@fail:
    jsr t1_print_fail

@idle:
    ; Failure stop loop.
	lda #$10
	jsr sys_sleep
    bra @idle
.endproc
