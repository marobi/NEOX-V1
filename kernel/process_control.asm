; ============================================================
; process_control.asm
; NEOX - process control / signals
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "signal.inc"

.export proc_terminate
.export proc_send_signal
.export proc_apply_signal

.import sched_debug_marker
.import sched_debug_pid

.import fd_close_process
.import wait_reason
.import wait_object
.import proc_exit_code

.import proc_state
.import proc_signal_pending

.import proc_set_state
.import proc_clear_wait

.segment "KERN_TEXT"

; ------------------------------------------------------------
; proc_terminate
;
; Input:
;   X = PID to terminate
;   A = exit code
;
; Return:
;   C clear = terminated
;   C set   = invalid target
;
; Effects:
;   - refuses to terminate PID 0
;   - closes all FDs
;   - clears wait state
;   - clears pending signal
;   - stores exit code
;   - marks process EMPTY
; ------------------------------------------------------------

.proc proc_terminate
    cpx #IDLE_PID
    beq @fail

    cpx #MAX_PROCS
    bcs @fail

    ldy proc_state,x
    cpy #PROC_EMPTY
    beq @fail

    ; Save exit code.
    sta proc_exit_code,x

    ; Close process-owned file descriptors.
    jsr fd_close_process

    ; Clear wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Clear pending process-control signal.
    stz proc_signal_pending,x

    ; Mark slot unused.
    lda #PROC_EMPTY
    jsr proc_set_state

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_send_signal
;
; Input:
;   X = target PID
;   A = signal
;
; Return:
;   C clear = accepted
;   C set   = invalid target
; ------------------------------------------------------------

.proc proc_send_signal
    cpx #IDLE_PID
    beq @fail

    cpx #MAX_PROCS
    bcs @fail

    ldy proc_state,x
    cpy #PROC_EMPTY
    beq @fail

    sta proc_signal_pending,x

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_apply_signal
;
; Input:
;   X = PID
;
; Return:
;   C clear
;
; Notes:
;   Applies one pending process-control signal.
; ------------------------------------------------------------

.proc proc_apply_signal
    lda proc_signal_pending,x
    beq @done

; debug
    lda #$09
    sta sched_debug_marker
; end debug

    stz proc_signal_pending,x

    cmp #SIG_HALT
    beq @halt

    cmp #SIG_CONT
    beq @cont

    cmp #SIG_KILL
    beq @kill

@done:
    clc
    rts

@halt:
    lda proc_state,x
    cmp #PROC_EMPTY
    beq @done

    cmp #PROC_STOPPED
    beq @done

    lda #PROC_STOPPED
    jsr proc_set_state

    clc
    rts

@cont:
    lda proc_state,x
    cmp #PROC_STOPPED
    bne @done

    lda #PROC_READY
    jsr proc_set_state

    clc
    rts

@kill:
    lda #$FF        ; killed by signal
    jsr proc_terminate
    clc
    rts
.endproc
