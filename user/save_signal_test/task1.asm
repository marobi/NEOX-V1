; ============================================================
; task1.asm
; NEOX - signal test controller task
;
; Temporary signal test image:
;   PID 1 sends SIG_HALT/SIG_CONT/SIG_KILL through sys_signal.
;   PID 2 is the runnable/yield target.
;   PID 3 is the timer-blocked target.
;
; Original freeze task saved as:
;   user/task1_freeze.asm
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "signal.inc"

.export user_task1_entry

T1_TARGET_RUN       = $02
T1_TARGET_SLEEP     = $03

.segment "USER_DATA"

t1_msg_start:
    .byte "T1 SIGCTL START", 13

t1_msg_halt_t2:
    .byte "T1 HALT PID2", 13

t1_msg_cont_t2:
    .byte "T1 CONT PID2", 13

t1_msg_halt_t3:
    .byte "T1 HALT PID3 WHILE TIM", 13

t1_msg_cont_t3:
    .byte "T1 CONT PID3", 13

t1_msg_kill_t2:
    .byte "T1 KILL PID2", 13

t1_msg_done:
    .byte "T1 SIGCTL DONE", 13

t1_msg_fail:
    .byte "T1 SIGNAL FAIL", 13

t1_wr_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; t1_print_msg
;
; Input:
;   A/X = message pointer
;   Y   = message length including CR
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

; ------------------------------------------------------------
; t1_sleep
;
; Input:
;   A = relative sleep ticks
; ------------------------------------------------------------

.proc t1_sleep
    jmp sys_sleep
.endproc

; ------------------------------------------------------------
; t1_send_signal
;
; Input:
;   A = signal
;   X = target PID
;
; Return:
;   C clear = accepted
;   C set   = failed
; ------------------------------------------------------------

.proc t1_send_signal
    jmp sys_signal
.endproc

.proc t1_print_start
    lda #<t1_msg_start
    ldx #>t1_msg_start
    ldy #16
    jmp t1_print_msg
.endproc

.proc t1_print_halt_t2
    lda #<t1_msg_halt_t2
    ldx #>t1_msg_halt_t2
    ldy #13
    jmp t1_print_msg
.endproc

.proc t1_print_cont_t2
    lda #<t1_msg_cont_t2
    ldx #>t1_msg_cont_t2
    ldy #13
    jmp t1_print_msg
.endproc

.proc t1_print_halt_t3
    lda #<t1_msg_halt_t3
    ldx #>t1_msg_halt_t3
    ldy #23
    jmp t1_print_msg
.endproc

.proc t1_print_cont_t3
    lda #<t1_msg_cont_t3
    ldx #>t1_msg_cont_t3
    ldy #13
    jmp t1_print_msg
.endproc

.proc t1_print_kill_t2
    lda #<t1_msg_kill_t2
    ldx #>t1_msg_kill_t2
    ldy #21
    jmp t1_print_msg
.endproc

.proc t1_print_done
    lda #<t1_msg_done
    ldx #>t1_msg_done
    ldy #15
    jmp t1_print_msg
.endproc

.proc t1_print_fail
    lda #<t1_msg_fail
    ldx #>t1_msg_fail
    ldy #15
    jmp t1_print_msg
.endproc

; ------------------------------------------------------------
; user_task1_entry
; ------------------------------------------------------------

.proc user_task1_entry
    jsr t1_print_start

    ; Let PID 2 enter its yield loop and PID 3 enter WAIT_TIMER.
    lda #$20
    jsr t1_sleep

    jsr t1_print_halt_t2
    lda #SIG_HALT
    ldx #T1_TARGET_RUN
    jsr t1_send_signal
    bcs @fail

    ; Leave PID 2 stopped long enough for ps inspection.
    lda #$40
    jsr t1_sleep

    jsr t1_print_cont_t2
    lda #SIG_CONT
    ldx #T1_TARGET_RUN
    jsr t1_send_signal
    bcs @fail

    lda #$20
    jsr t1_sleep

    ; PID 3 should still be blocked on its long timer here.
    jsr t1_print_halt_t3
    lda #SIG_HALT
    ldx #T1_TARGET_SLEEP
    jsr t1_send_signal
    bcs @fail

    ; Wait long enough for PID 3 timer expiry.  This must exceed
    ; PID 3's remaining timer interval after SIG_HALT is queued.
    ; Expected behavior:
    ;   scheduler_wake_timers wakes PID 3, then the scheduler signal
    ;   phase applies SIG_HALT and leaves PID 3 stopped.
    lda #$FF
    jsr t1_sleep

    jsr t1_print_cont_t3
    lda #SIG_CONT
    ldx #T1_TARGET_SLEEP
    jsr t1_send_signal
    bcs @fail

    lda #$30
    jsr t1_sleep

    ; SIG_KILL now marks PID 2 as PROC_ZOMBIE.  The idle reaper
    ; performs final termination outside the scheduler signal phase.
    jsr t1_print_kill_t2
    lda #SIG_KILL
    ldx #T1_TARGET_RUN
    jsr t1_send_signal
    bcs @fail

    jsr t1_print_done

@idle:
    lda #$40
    jsr t1_sleep
    bra @idle

@fail:
    jsr t1_print_fail

@fail_idle:
    lda #$40
    jsr t1_sleep
    bra @fail_idle
.endproc
