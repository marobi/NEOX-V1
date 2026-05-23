; ============================================================
; supervisor.asm
; NEOX - MICMON supervisor entry/exit
;
; Model:
;   Entering monitor freezes the scheduler state as-is.
;   Leaving monitor only re-enables scheduling.
;
; The supervisor does not:
;   - save or alter current process state
;   - change current_pid
;   - change proc_state
;   - touch console ownership/wait state
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "process.inc"
.include "scheduler_defs.inc"

.import ksys_io_lock

.import monitor_pending
.import sched_lock
.import fd_lock
.import pipe_lock
.import rp_lock

.export enter_monitor
.export leave_monitor
.export supervisor_try_enter_pending

.import current_pid
.import proc_context
.import proc_sp

.import console_monitor_enter
.import console_monitor_exit

.import sched_lock_enter
.import sched_lock_leave

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B000

.segment "KERN_TEXT"

; ------------------------------------------------------------
; supervisor_monitor_safe
;
; Return:
;   C clear = safe to enter monitor
;   C set   = unsafe
;
; Policy:
;   Monitor entry is cooperative only. It may happen only when
;   no non-reentrant subsystem lock is held.
;
; Locks checked:
;   sched_lock - monitor/scheduler critical section
;   fd_lock    - FD/open-object tables
;   pipe_lock  - pipe tables/buffers
;   rp_lock    - RP mailbox/request block
; ------------------------------------------------------------

.proc supervisor_monitor_safe
    lda sched_lock
    bne @unsafe

	lda fd_lock
	ora pipe_lock
	ora rp_lock
	ora ksys_io_lock
	bne @unsafe
	
    clc
    rts

@unsafe:
    sec
    rts
.endproc

; ------------------------------------------------------------
; supervisor_try_enter_pending
;
; Called from cooperative safe points.
;
; Return:
;   RTS if no monitor request is pending or entry is unsafe.
;   Does not return here if monitor is entered.
;
; Stack model:
;   This routine is called with JSR from sched_yield. If monitor
;   is entered, enter_monitor saves the current stack. On monitor
;   exit, execution resumes at the return address of that JSR,
;   so sched_yield continues normally.
;
; Notes:
;   IRQ only sets monitor_pending. It never jumps to MICMON.
;   This is the single deferred monitor-entry path.
; ------------------------------------------------------------

.proc supervisor_try_enter_pending
    php
    sei

    lda monitor_pending
    beq @done

    jsr supervisor_monitor_safe
    bcs @done

    stz monitor_pending

    ; Restore caller's original P before entering MICMON.
    ; enter_monitor is the only monitor entry path.
    plp
    jmp enter_monitor

@done:
    plp
    rts
.endproc

; ------------------------------------------------------------
; enter_monitor
;
; Freeze scheduler and enter MICMON from a cooperative safe point.
; ------------------------------------------------------------

.proc enter_monitor
    ; Save current task stack pointer.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    jsr sched_lock_enter

	jsr console_monitor_enter
	
    lda #MONITOR_CONTEXT
    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; leave_monitor
;
; Purpose:
;   Leave MICMON and resume normal scheduling.
;
;   - restore caller stack/context
;   - return through RTS path
; ------------------------------------------------------------

.proc leave_monitor
    sei

	jsr console_monitor_exit
	
    ; Restore interrupted task stack pointer.
    ldx current_pid
    lda proc_sp,x
    tax
    txs

    ; Restore interrupted context.
    ldx current_pid
    lda proc_context,x

    jsr sched_lock_leave
	
    ldx #<resume_rts_from_monitor
    ldy #>resume_rts_from_monitor
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; resume_rts_from_monitor
;
; RTS-style monitor return trampoline.
; ------------------------------------------------------------

.proc resume_rts_from_monitor
	cli
	rts
.endproc
