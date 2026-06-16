; ============================================================
; task3.asm
; NEOX - signal test timer-blocked target
;
; Temporary signal test image:
;   PID 3 blocks in sys_sleep with WAIT_TIMER.
;   PID 1 sends SIG_HALT while this task is blocked.
;
; Original freeze task saved as:
;   user/task3_freeze.asm
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task3_entry

.segment "USER_DATA"

t3_msg_start:
    .byte "T3 TIMER TARGET START", 13

t3_msg_sleep:
    .byte "T3 SLEEP", 13

t3_msg_woke:
    .byte "T3 WOKE", 13

t3_wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; t3_print_msg
;
; Input:
;   A/X = message pointer
;   Y   = message length including CR
; ------------------------------------------------------------

.proc t3_print_msg
    sta t3_wr_stdout_args + rw_args::buf_ptr
    stx t3_wr_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t3_wr_stdout_args + rw_args::len
    stz t3_wr_stdout_args + rw_args::len + 1

    SYSCALL t3_wr_stdout_args, sys_write
    rts
.endproc

.proc t3_print_start
    lda #<t3_msg_start
    ldx #>t3_msg_start
    ldy #22
    jmp t3_print_msg
.endproc

.proc t3_print_sleep
    lda #<t3_msg_sleep
    ldx #>t3_msg_sleep
    ldy #9
    jmp t3_print_msg
.endproc

.proc t3_print_woke
    lda #<t3_msg_woke
    ldx #>t3_msg_woke
    ldy #8
    jmp t3_print_msg
.endproc

; ------------------------------------------------------------
; user_task3_entry
; ------------------------------------------------------------

.proc user_task3_entry
    jsr t3_print_start

    jsr t3_print_sleep

    ; Long sleep gives PID 1 a stable window to send SIG_HALT while
    ; this task is blocked on WAIT_TIMER.
    lda #$F0
    jsr sys_sleep

    ; This line should not print until PID 1 sends SIG_CONT after
    ; the timer has expired and the scheduler phase has stopped PID 3.
    jsr t3_print_woke

@quiet_loop:
    ; Keep PID 3 alive without flooding the console after the
    ; controlled blocked-signal test has completed.
    lda #$F0
    jsr sys_sleep
    bra @quiet_loop
.endproc
