; ============================================================
; process_control.asm
; NEOX - process control / signals
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "signal.inc"

.export proc_find_free_pid
.export proc_create
.export proc_terminate
.export proc_send_signal
.export proc_apply_signal

.import sched_lock_enter
.import sched_lock_leave
.import fd_init_process
.import fd_close_process

.import current_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_resume_mode
.import proc_parent_pid
.import proc_signal_pending
.import proc_exit_code

.import wait_reason
.import wait_object

.import proc_set_state

.importzp sched_ptr

.segment "KERN_TEXT"

; ------------------------------------------------------------
; proc_find_free_pid
;
; Return:
;   C set   = found, X = free pid
;   C clear = none available
;
; Notes:
;   PID 0 is reserved for idle/supervisor fallback.
; ------------------------------------------------------------

.proc proc_find_free_pid
    ldx #$01

@scan:
    lda proc_state,x
    beq @found

    inx
    cpx #MAX_PROCS
    bne @scan

    clc
    rts

@found:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_create
;
; Inputs:
;   X/Y = pointer to proc_create_args
;
; Return:
;   C clear = success
;             A = allocated PID
;
;   C set   = failure
;
; Notes:
;   - PID is allocated by the kernel.
;   - context 0 is reserved for idle/supervisor/monitor.
;   - state is written last so partially initialized slots are
;     never visible as runnable.
; ------------------------------------------------------------

.proc proc_create
    stx sched_ptr
    sty sched_ptr+1

    ; Context 0 is reserved for idle/supervisor/monitor.
    ; Normal processes must not be created in context 0.
    ldy #proc_create_args::context
    lda (sched_ptr),y
    beq @fail

    jsr proc_find_free_pid
    bcc @fail

    jsr sched_lock_enter

    ; Save MMU context id.
    ldy #proc_create_args::context
    lda (sched_ptr),y
    sta proc_context,x

    ; Save first-run entry address.
    ldy #proc_create_args::entry
    lda (sched_ptr),y
    sta proc_entryL,x

    iny
    lda (sched_ptr),y
    sta proc_entryH,x

    ; Record parent PID.
    lda current_pid
    sta proc_parent_pid,x

    ; Initial task stack.
    lda #$FF
    sta proc_sp,x

    ; Initial wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Initial pending signal.
    stz proc_signal_pending,x

    ; Initial exit code.
    lda #EXIT_OK
    sta proc_exit_code,x

    ; Initial resume mode.
    lda #PROC_RESUME_RTS
    sta proc_resume_mode,x

    ; Initial process flags.
    lda #PROC_FLAG_NONE
    sta proc_flags,x

    ; Initialise FD list.
    jsr fd_init_process

    ; Publish process last.
    lda #PROC_NEW
    jsr proc_set_state

    jsr sched_lock_leave

    txa
    clc
    rts

@fail:
    sec
    rts
.endproc

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

; ------------------------------------------------------------
; proc_terminate
;
; Input:
;   X = PID to terminate
;   A = exit code
;
; Notes:
;   - PID 0 must never be terminated.
;   - fd_close_process clobbers X.
;   - Preserve target PID with PHX/PLX.
;   - Mark PROC_EMPTY last.
; ------------------------------------------------------------

.proc proc_terminate
    cpx #IDLE_PID
    beq @done

    cpx #MAX_PROCS
    bcs @done

    ; Store exit code while X still contains target PID.
    sta proc_exit_code,x

    ; fd_close_process clobbers X.
    phx
    jsr fd_close_process
    plx

    ; Clear wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Clear pending signal state.
    stz proc_signal_pending,x

    ; Clear execution/context fields.
    lda #$FF
    ; Mark parent invalid for an empty slot.
    sta proc_parent_pid,x
    sta proc_context,x
    
	stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x
    stz proc_resume_mode,x

    ; Mark parent invalid for an empty slot.
    lda #$FF
    sta proc_parent_pid,x

    ; Mark process empty last.
    lda #PROC_EMPTY
    sta proc_state,x

@done:
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
