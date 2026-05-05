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

.include "../bios/bios.inc"

.export enter_monitor_irq
.export enter_monitor_syscall
.export leave_monitor

.import current_pid
.import proc_context
.import proc_sp
.import monitor_return_mode

.import sched_lock_enter
.import sched_lock_leave

MONITOR_RET_RTI     = $01
MONITOR_RET_RTS     = $02

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B000

.segment "KERN_TEXT"

; ------------------------------------------------------------
; enter_monitor_irq
;
; Freeze scheduler and enter MICMON.
; Return path uses BIOS_CONTEXT_RTI.
; ------------------------------------------------------------

.proc enter_monitor_irq
    lda #MONITOR_RET_RTI
    bra enter_monitor_common
.endproc

; ------------------------------------------------------------
; enter_monitor_syscall
;
; Freeze scheduler and enter MICMON.
; Return path uses RTS trampoline.
; ------------------------------------------------------------

.proc enter_monitor_syscall
    lda #MONITOR_RET_RTS
    bra enter_monitor_common
.endproc

;
;
;
.proc enter_monitor_common
    sta monitor_return_mode

    ; Save interrupted task SP. Do not change process state.
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
;   Leave MICMON and return to the process that was current when
;   monitor was entered.
;
; Scheduler model:
;   Monitor entry froze scheduling with sched_lock_enter.
;   Monitor exit releases that lock, but does not alter process state.
;
; Important:
;   Even though scheduler state is frozen, we must still restore the
;   MMU context for current_pid before returning from monitor.
; ------------------------------------------------------------

.proc leave_monitor
    sei

    ; Release scheduler before restoring task stack.
    jsr sched_lock_leave

    ; Restore interrupted task stack pointer.
    ldx current_pid
    lda proc_sp,x
    tax
    txs

    ; Return in current process context.
    ldx current_pid
    lda proc_context,x

    lda monitor_return_mode
    cmp #MONITOR_RET_RTS
    beq @return_rts

    jmp BIOS_CONTEXT_RTI

@return_rts:
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
    rts
.endproc
