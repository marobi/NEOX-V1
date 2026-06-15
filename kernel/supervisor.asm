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
.include "debug.inc"
.include "sched_lock.inc"

.export enter_monitor
.export leave_monitor
.export supervisor_enter_from_irq

.import active_pid
.import active_context

.import console_monitor_enter
.import console_monitor_exit

.import irq_restore

MONITOR_CONTEXT     = $00
MONITOR_ENTRY       = $B003

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
; Called directly from irq_entry for RP_IRQ_SRC_MONITOR via JMP
;
; Stack on entry:
;   irq_entry has already pushed A, X, Y.
;   Below that is the hardware IRQ return frame.
;
; The saved return context is active_context, not a lookup
; through scheduler cursor state. active_pid is the interrupted
; process identity at this boundary.
; ------------------------------------------------------------

.proc supervisor_enter_from_irq
    sei

    ldy active_pid
    sty supervisor_saved_pid

    lda active_context
    sta supervisor_saved_context

    tsx
    stx supervisor_saved_sp

    lda #SUP_RETURN_IRQ
    sta supervisor_saved_return_mode

    jsr sched_lock_try_enter
    bcs busy_restore_irq

    jsr console_monitor_enter

    ; The interrupted context was saved in supervisor_saved_context.
    ; From this point the active execution context becomes MICMON.
    ; Publish PID 0 together with context 0 so monitor-side ps never
    ; observes an impossible user PID / supervisor-context pair.
    stz active_pid
    lda #MONITOR_CONTEXT
    sta active_context

    ; A still contains MONITOR_CONTEXT after publishing active_context.
    BIOS_CONTEXT_SWITCH
    jmp MONITOR_ENTRY

busy_restore_irq:
    ; sched_lock was already held.  Do not enter monitor from inside
    ; a scheduler-critical section; restore the interrupted context.
    jmp irq_restore
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
    ldy active_pid
    sty supervisor_saved_pid

    lda active_context
    sta supervisor_saved_context

    tsx
    stx supervisor_saved_sp

    lda #SUP_RETURN_RTS
    sta supervisor_saved_return_mode

    jsr sched_lock_try_enter
    bcs busy_rts

    jsr console_monitor_enter

    ; The return context was saved in supervisor_saved_context.
    ; From this point the active execution context becomes MICMON.
    ; Publish PID 0 together with context 0 so monitor-side ps never
    ; observes an impossible user PID / supervisor-context pair.
    stz active_pid
    lda #MONITOR_CONTEXT
    sta active_context

    ; A still contains MONITOR_CONTEXT after publishing active_context.
    BIOS_CONTEXT_SWITCH
    jmp MONITOR_ENTRY

busy_rts:
    ; Manual monitor entry cannot proceed while scheduler state is
    ; locked.  The try-lock restored the caller's P on failure.
    rts
.endproc

; ------------------------------------------------------------
; leave_monitor
;
; Leave MICMON and resume the exact saved continuation.
; ------------------------------------------------------------

.proc leave_monitor
    sei

    jsr console_monitor_exit

    lda supervisor_saved_return_mode
    cmp #SUP_RETURN_IRQ
    beq return_irq

return_rts:
    lda supervisor_saved_pid
    sta active_pid
    lda supervisor_saved_context
    sta active_context

    ; A still contains the saved context after publishing active_context.
    BIOS_CONTEXT_SWITCH

    ldx supervisor_saved_sp
    txs

    jsr sched_lock_leave

    jmp resume_rts_from_monitor

return_irq:
    lda supervisor_saved_pid
    sta active_pid
    lda supervisor_saved_context
    sta active_context

    ; A still contains the saved context after publishing active_context.
    BIOS_CONTEXT_SWITCH

    ldx supervisor_saved_sp
    txs

    jsr sched_lock_leave

    jmp irq_restore
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
