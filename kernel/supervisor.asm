; ============================================================
; supervisor.asm
; NEOX - MICMON supervisor entry/exit
;
; Model:
;   Entering monitor freezes the current 6502 continuation.
;   MICMON uses BIOS low-level raw get/put-char only.
;   It must not call kernel syscalls, FD, pipe, ksys_io, RP mailbox,
;   scheduler services, or any other inspected subsystem.
;
; Return modes:
;   - RTS mode: manual/cooperative entry through enter_monitor
;   - IRQ mode: monitor IRQ entry through supervisor_enter_from_irq
; ============================================================

.setcpu "65C02"

.include "bios.inc"

.export enter_monitor
.export leave_monitor
.export supervisor_enter_from_irq

.import current_pid
.import active_context

.import console_monitor_enter
.import console_monitor_exit

.import sched_lock_enter
.import sched_lock_leave

.import irq_restore

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B000

SUP_RETURN_RTS      = $00
SUP_RETURN_IRQ      = $01

.segment "KERN_BSS"

supervisor_saved_pid:
    .res 1

supervisor_saved_sp:
    .res 1

supervisor_saved_context:
    .res 1

supervisor_saved_return_mode:
    .res 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; supervisor_enter_from_irq
;
; Called directly from irq_entry for RP_IRQ_SRC_MONITOR.
;
; Stack on entry:
;   irq_entry has already pushed A, X, Y.
;   Below that is the hardware IRQ return frame.
;
; The saved return context is active_context, not
; proc_context[current_pid]. During scheduler handoff current_pid
; may already point to the selected process while the CPU is still
; executing in the previous context.
; ------------------------------------------------------------

.proc supervisor_enter_from_irq
    sei

    ldy current_pid
    sty supervisor_saved_pid

    lda active_context
    sta supervisor_saved_context

    tsx
    stx supervisor_saved_sp

    lda #SUP_RETURN_IRQ
    sta supervisor_saved_return_mode

    jsr sched_lock_enter

    jsr console_monitor_enter

    ; The interrupted context was saved in supervisor_saved_context.
    ; From this point the active execution context becomes MICMON.
    lda #MONITOR_CONTEXT
    sta active_context

    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; enter_monitor
;
; Manual/cooperative monitor entry.
;
; This path saves the current RTS-style continuation and returns
; through resume_rts_from_monitor on monitor exit.
; ------------------------------------------------------------

.proc enter_monitor
    ldy current_pid
    sty supervisor_saved_pid

    lda active_context
    sta supervisor_saved_context

    tsx
    stx supervisor_saved_sp

    lda #SUP_RETURN_RTS
    sta supervisor_saved_return_mode

    jsr sched_lock_enter

    jsr console_monitor_enter

    ; The return context was saved in supervisor_saved_context.
    ; From this point the active execution context becomes MICMON.
    lda #MONITOR_CONTEXT
    sta active_context

    ldx #<MONITOR_ENTRY
    ldy #>MONITOR_ENTRY
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; leave_monitor
;
; Leave MICMON and resume the exact saved continuation.
; ------------------------------------------------------------

.proc leave_monitor
    sei

    jsr console_monitor_exit

    ldx supervisor_saved_sp
    txs

    lda supervisor_saved_return_mode
    pha

    jsr sched_lock_leave

    pla
    cmp #SUP_RETURN_IRQ
    beq @return_irq

@return_rts:
    lda supervisor_saved_context
    sta active_context
    ldx #<resume_rts_from_monitor
    ldy #>resume_rts_from_monitor
    jmp BIOS_CONTEXT_JUMP

@return_irq:
    lda supervisor_saved_context
    sta active_context
    ldx #<irq_restore
    ldy #>irq_restore
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
