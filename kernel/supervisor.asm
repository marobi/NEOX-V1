; ============================================================
; supervisor.asm
; NEOX - explicit entry into monitor/supervisor process 0
;
; Purpose:
;   Provides controlled transfer from a running task into the
;   monitor process descriptor (pid 0), and controlled return
;   back to the previously interrupted task.
;
; Design:
;   - pid 0 is a real process-table entry
;   - pid 0 is not part of normal round-robin scheduling
;   - entering monitor is always treated as a fresh first run
;   - leaving monitor resumes the previously saved task
;   - scheduler is frozen while MICMON is active
;
; Notes:
;   - first_run_entry now lives in scheduler.asm
;   - proc_first_run no longer exists
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "process.inc"
.include "bios.inc"

.export enter_monitor_irq
.export enter_monitor_syscall
.export leave_monitor
.export resume_rts_from_monitor

.import first_run_entry
.import sched_lock_enter
.import sched_lock_leave

.import current_pid
.import proc_state
.import proc_context
.import proc_sp
.import saved_task_pid
.import console_owner_pid
.import monitor_return_mode

MONITOR_RET_RTI     = $01
MONITOR_RET_RTS     = $02

.segment "KERN_TEXT"

; ------------------------------------------------------------
; enter_monitor_irq
;
; Purpose:
;   Enter monitor from an IRQ-driven path.
;
; Entry conditions:
;   - entered from irq_entry
;   - interrupted task already has hardware IRQ frame plus
;     saved A/X/Y on its private stack
;
; Behavior:
;   - save interrupted task SP
;   - remember interrupted task pid
;   - mark interrupted task READY
;   - record IRQ-style return mode
;   - freeze scheduling while MICMON is active
;   - switch to pid 0 through first_run_entry
;
; Notes:
;   Monitor entry is always a fresh first run of pid 0.
;   It does not resume an old monitor stack.
; ------------------------------------------------------------

.proc enter_monitor_irq
    ; Save interrupted task SP
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Remember which task we interrupted
    sty saved_task_pid

    ; Interrupted task becomes runnable again
    lda #PROC_READY
    sta proc_state,y

    ; Returning from monitor must resume through RTI semantics
    lda #MONITOR_RET_RTI
    sta monitor_return_mode

    ; Freeze normal scheduling while MICMON is active
    jsr sched_lock_enter

    ; pid 0 owns the console while monitor is active
    stz current_pid
    stz console_owner_pid

    ; pid 0 is now considered running
    lda #PROC_RUNNING
    sta proc_state+0

    ; Switch to context 0 and enter the inline first-run
    ; bootstrap in scheduler.asm.
    lda proc_context+0
    ldx #<first_run_entry
    ldy #>first_run_entry
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; enter_monitor_syscall
;
; Purpose:
;   Enter monitor from a syscall path.
;
; Entry conditions:
;   - current task is running normally
;   - no IRQ-style frame is required for entry
;
; Behavior:
;   - save current task SP
;   - remember current task pid
;   - mark current task READY
;   - record syscall-style return mode
;   - freeze scheduling while MICMON is active
;   - switch to pid 0 through first_run_entry
;
; Notes:
;   Monitor entry is always a fresh first run of pid 0.
; ------------------------------------------------------------

.proc enter_monitor_syscall
    ; Save current task SP
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Remember which task requested monitor entry
    sty saved_task_pid

    ; Calling task becomes runnable again
    lda #PROC_READY
    sta proc_state,y

    ; Returning from monitor must resume through RTS semantics
    lda #MONITOR_RET_RTS
    sta monitor_return_mode

    ; Freeze normal scheduling while MICMON is active
    jsr sched_lock_enter

    ; pid 0 owns the console while monitor is active
    stz current_pid
    stz console_owner_pid

    ; pid 0 is now considered running
    lda #PROC_RUNNING
    sta proc_state+0

    ; Switch to context 0 and enter the inline first-run
    ; bootstrap in scheduler.asm.
    lda proc_context+0
    ldx #<first_run_entry
    ldy #>first_run_entry
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; leave_monitor
;
; Purpose:
;   Leave MICMON and resume the previously saved task.
;
; Behavior:
;   - restore task identity
;   - mark that task RUNNING again
;   - release scheduler lock before touching SP
;   - restore saved task SP
;   - resume through RTI or RTS depending on entry path
;
; Critical rule:
;   After TXS, no subroutine calls are performed.
; ------------------------------------------------------------

.proc leave_monitor
    ; Restore the task that was active before monitor entry
    lda saved_task_pid
    sta current_pid
;    sta console_owner_pid

    tax
    lda #PROC_RUNNING
    sta proc_state,x

    ; Release scheduler freeze BEFORE restoring task SP
    jsr sched_lock_leave

    ; Restore saved SP for the task we are about to resume
    lda proc_sp,x
    tax
    txs

    ; Decide how to resume that task
    lda monitor_return_mode
    cmp #MONITOR_RET_RTS
    beq @resume_rts

    ; Default: IRQ-style resume
    ldx current_pid
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@resume_rts:
    ; Syscall-style resume:
    ; switch to the task context, then execute RTS there.
    ldx current_pid
    lda proc_context,x
    ldx #<resume_rts_from_monitor
    ldy #>resume_rts_from_monitor
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; resume_rts_from_monitor
;
; Purpose:
;   Shared stub used to resume a syscall-entered task after
;   monitor exit.
;
; Behavior:
;   Executes RTS in the restored task context.
;
; Notes:
;   Arrives here only after BIOS_CONTEXT_JUMP has already
;   switched to the correct task context.
; ------------------------------------------------------------

.proc resume_rts_from_monitor
    rts
.endproc
