; ============================================================
; supervisor.asm
; NEOX - MICMON supervisor entry/exit
;
; Model:
;   - PID 0 is the idle process.
;   - MICMON is not a process.
;   - MICMON runs directly in context 0 at $B000.
;   - current_pid remains the interrupted scheduler PID while
;     MICMON is active.
;   - scheduler is locked while MICMON is active.
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "../bios/bios.inc"

.export enter_monitor_irq
.export enter_monitor_syscall
.export leave_monitor
.export resume_rts_from_monitor

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

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B000

.segment "KERN_TEXT"

.proc enter_monitor_irq
    ; Save interrupted task/idle SP.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Remember interrupted scheduler PID.
    sty saved_task_pid

    ; Current RUNNING process becomes READY while monitor runs.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @state_done

    tya
    tax
    lda #PROC_READY
    sta proc_state,x

@state_done:
    lda #MONITOR_RET_RTI
    sta monitor_return_mode

    ; Freeze scheduler while MICMON owns the machine.
    jsr sched_lock_enter

    ; Monitor is not PID 0. Do not fake ownership.
    lda #$FF
    sta console_owner_pid

    ; Enter MICMON directly in context 0.
    lda #MONITOR_CONTEXT
    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

.proc enter_monitor_syscall
    ; Save current task/idle SP.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Remember requesting scheduler PID.
    sty saved_task_pid

    ; Current RUNNING process becomes READY while monitor runs.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @state_done

    tya
    tax
    lda #PROC_READY
    sta proc_state,x

@state_done:
    lda #MONITOR_RET_RTS
    sta monitor_return_mode

    ; Freeze scheduler while MICMON owns the machine.
    jsr sched_lock_enter

    ; Monitor is not PID 0. Do not fake ownership.
    lda #$FF
    sta console_owner_pid

    ; Enter MICMON directly in context 0.
    lda #MONITOR_CONTEXT
    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

.proc leave_monitor
	sei
    ; Restore interrupted scheduler PID.
    lda saved_task_pid
    sta current_pid
    tax

    ; Mark it running again.
    lda #PROC_RUNNING
    sta proc_state,x

    ; Restore saved task SP.
    lda proc_sp,x
    tax
    txs

    ; After TXS, do not JSR.
    lda monitor_return_mode
    cmp #MONITOR_RET_RTS
    beq @resume_rts

    ; IRQ-style return.
    ldx current_pid
    lda proc_context,x

    ; Release scheduler freeze before restoring task stack.
    jsr sched_lock_leave

    cli
	jmp BIOS_CONTEXT_RTI

@resume_rts:
    ; Syscall-style return.
    ldx current_pid
    lda proc_context,x
    ldx #<resume_rts_from_monitor
    ldy #>resume_rts_from_monitor

	cli
    jmp BIOS_CONTEXT_JUMP
.endproc

.proc resume_rts_from_monitor
    rts
.endproc
