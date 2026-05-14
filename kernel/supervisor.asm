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

.export enter_monitor_irq
.export enter_monitor_syscall
.export leave_monitor

;---------------------------------------------------
.import sched_debug_marker
.import sched_debug_pid
.import sched_debug_old_state
.import sched_debug_old_pid
;---------------------------------------------------

.import current_pid
.import proc_context
.import proc_sp
.import monitor_return_mode
.import proc_state
.import proc_resume_mode
.import proc_set_ready
.import sched_yield

.import sched_lock_enter
.import sched_lock_leave

MONITOR_RET_IRQ     = $01
MONITOR_RET_RTS     = $02

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B000

.segment "KERN_TEXT"

; ------------------------------------------------------------
; enter_monitor_irq
;
; Enter monitor from IRQ.
;
; irq_entry has already pushed A/X/Y.
;
; If a normal process was interrupted, save it as RTI-resumable
; and demote RUN -> READY.
;
; If PID 0 was interrupted, do not save/demote it as a normal
; process. PID 0 is idle/supervisor fallback.
; ------------------------------------------------------------

.proc enter_monitor_irq
    lda #$07
    sta sched_debug_marker

    lda current_pid
    sta sched_debug_pid

    ; Interrupted owner.
    ldy current_pid

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    ; --------------------------------------------------------
    ; PID 0 is not a normal task.
    ; Do not save proc_sp[0].
    ; Do not set proc_resume_mode[0].
    ; Do not convert PID 0 RUN -> READY.
    ; --------------------------------------------------------

    cpy #IDLE_PID
    beq @enter_monitor

    ; Save interrupted normal process stack.
    tsx
    txa
    sta proc_sp,y

    ; IRQ-created stack resumes by RTI.
    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    ; Demote interrupted normal RUN process.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @enter_monitor

    lda #$0A
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    tya
    tax
    jsr proc_set_ready

@enter_monitor:
    lda #IDLE_PID
    sta current_pid

    lda #MONITOR_RET_IRQ
    sta monitor_return_mode

    jsr sched_lock_enter

    lda #MONITOR_CONTEXT
    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; enter_monitor_syscall
;
; Freeze scheduler and enter MICMON from syscall/user context.
; This remains RTS-style for now.
; ------------------------------------------------------------

.proc enter_monitor_syscall
    lda #MONITOR_RET_RTS
    sta monitor_return_mode

    ; Save current task stack pointer.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    jsr sched_lock_enter

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
; IRQ-entered monitor:
;   - interrupted task was already saved during
;     enter_monitor_irq
;   - current_pid was switched to IDLE_PID
;   - resume through normal sched_yield path
;
; Syscall-entered monitor:
;   - restore caller stack/context
;   - return through RTS path
; ------------------------------------------------------------

.proc leave_monitor
    sei

    lda monitor_return_mode
    cmp #MONITOR_RET_IRQ
    beq @return_scheduler

    cmp #MONITOR_RET_RTS
    beq @return_rts

    ; Unknown mode -> safest fallback.
@return_scheduler:
    jsr sched_lock_leave
; debug
    lda #$08
    sta sched_debug_marker

    lda current_pid
    sta sched_debug_pid
; end debug
    jmp sched_yield

@return_rts:
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
