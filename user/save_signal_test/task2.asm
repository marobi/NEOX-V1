; ============================================================
; task2.asm
; NEOX - signal test runnable/yield target
;
; Temporary signal test image:
;   PID 2 stays runnable by yielding repeatedly.
;   PID 1 sends STOP/CONT/KILL signals to this task.
;
; Original freeze task saved as:
;   user/task2_freeze.asm
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task2_entry

.segment "USER_DATA"

t2_msg_start:
    .byte "T2 RUN TARGET START", 13

t2_wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; t2_print_msg
;
; Input:
;   A/X = message pointer
;   Y   = message length including CR
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
    ldy #20
    jmp t2_print_msg
.endproc


; ------------------------------------------------------------
; user_task2_entry
; ------------------------------------------------------------

.proc user_task2_entry
    jsr t2_print_start

@loop:
    ; Keep PID 2 runnable without flooding the console.
    ; PID 1 controller messages and ps snapshots are the signal-test output.
    jsr sys_yield
    bra @loop
.endproc
