; ============================================================
; irq.asm
; NEOX - IRQ / NMI entry handling
;
; Purpose:
;   Handles hardware IRQ entry on the 6502 side and dispatches
;   to the correct kernel action based on the IRQ source.
;
; Architecture:
;   - BIOS owns the real CPU vectors and jumps here
;   - Context 0 is supervisor / MICMON
;   - Contexts 1..N are schedulable tasks
;   - Timer IRQ drives normal scheduling
;   - RP2350 may also request entry into MICMON
;
; IRQ policy:
;   1. Save A/X/Y onto the interrupted context stack.
;   2. Read and acknowledge the RP IRQ source through BIOS_ACK_IRQ.
;   3. If source = monitor request:
;        -> enter MICMON immediately through supervisor_enter_from_irq
;        -> preserve the current IRQ stack as the frozen continuation
;        -> return later through irq_restore / RTI
;   4. If source = timer tick:
;        -> count the tick
;        -> if sched_lock or rp_lock is held, resume unchanged
;        -> else perform normal scheduler context switch
;   5. All other IRQ sources:
;        -> restore interrupted context unchanged
;
; Stack model:
;   On hardware IRQ entry, CPU has already pushed:
;       PCH, PCL, SR
;
;   This file extends the frame by pushing:
;       A, X, Y
;
;   So sched_context_switch may later restore with:
;       PLY / PLX / PLA / RTI
;
;   Monitor entry is immediate/freeze-style and does not use the scheduler.
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "mailbox.inc"
.include "debug.inc"

.export irq_entry
.export nmi_entry

.import brk_vector

.import supervisor_enter_from_irq

.import scheduler_irq_tick
.import sched_context_switch
.import sched_lock
.import console_owner_pid
.import monitor_active

.import rp_lock

.import file_io_gate
.import proc_gate

.segment "KERN_TEXT"

; ------------------------------------------------------------
; irq_entry
;
; Purpose:
;   Main kernel IRQ entry point.
;
; Inputs:
;   None explicitly.
;   CPU arrives here from hardware IRQ with interrupt frame
;   already stacked by the processor.
;
; Outputs:
;   Does not return normally.
;
; Either:
;   - restores interrupted context and RTI
;   - enters MICMON immediately for a monitor request
;   - or transfers to scheduler switch logic for a timer IRQ
;
; Clobbers:
;   A, X, Y
;
; Notes:
;   The interrupted context is preserved on its private stack
;   until a dispatch decision is made.
; ------------------------------------------------------------

.proc irq_entry
	sei
    pha
    phx
    phy

    ; BRK uses the IRQ vector but is not an RP IRQ.
    ; Test the stacked status B flag before reading/ACKing
    ; RP_IRQ_SOURCE. Otherwise BRK with RP_IRQ_SOURCE = NONE would
    ; be misclassified as "no IRQ" and restored immediately.
    tsx
    lda $0104,x
    and #$10
    bne brk_entry				; BREAK

    lda RP_IRQ_SOURCE
	jsr BIOS_ACK_IRQ			; ack IRQ
	
	cmp #RP_IRQ_SRC_NONE		; non IRQ
	beq irq_restore

    cmp #RP_IRQ_SRC_TIMER		; TIMER IRQ
    beq @timer

    cmp #RP_IRQ_SRC_MONITOR		; MONITOR IRQ
    beq @monitor

    ; unknown → just return
    bra irq_restore

@monitor:
    jmp supervisor_enter_from_irq	; must be JMP
	
@timer:
    lda monitor_active
    beq @not_monitor

    ; DEBUG-BEGIN: temporary IRQ preemption skipped by monitor flag
    lda #DBG_IRQ_SKIP_MONITOR
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption skipped by monitor flag
    jmp irq_restore

@not_monitor:
    jsr scheduler_irq_tick

    lda sched_lock
    beq @sched_free

    ; DEBUG-BEGIN: temporary IRQ preemption skipped by sched_lock
    lda #DBG_IRQ_SKIP_SCHED
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption skipped by sched_lock
    jmp irq_restore

@sched_free:
    lda rp_lock
    beq @rp_free

    ; DEBUG-BEGIN: temporary IRQ preemption skipped by rp_lock
    lda #DBG_IRQ_SKIP_RP
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption skipped by rp_lock
    jmp irq_restore

@rp_free:
    lda file_io_gate
    beq @fileio_free

    ; DEBUG-BEGIN: temporary IRQ preemption skipped by file_io_gate
    lda #DBG_IRQ_SKIP_FILEIO
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption skipped by file_io_gate
    jmp irq_restore

@fileio_free:
    lda proc_gate
    beq @preempt

    ; DEBUG-BEGIN: temporary IRQ preemption skipped by proc_gate
    lda #DBG_IRQ_SKIP_PROC
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption skipped by proc_gate
    jmp irq_restore

@preempt:
    ; DEBUG-BEGIN: temporary IRQ preemption entered scheduler
    lda #DBG_IRQ_ENTER_SWITCH
    sta dbg_irq_skip_reason
    ; DEBUG-END: temporary IRQ preemption entered scheduler
    jmp sched_context_switch
.endproc

;
	.export irq_restore
irq_restore:
    ply
    plx
    pla
    rti

.proc brk_entry
	jmp (brk_vector)
.endproc

; ------------------------------------------------------------
; nmi_entry
;
; Purpose:
;   Minimal NMI handler stub.
;
; Notes:
;   No NMI-specific functionality is implemented yet.
; ------------------------------------------------------------

.proc nmi_entry
    rti
.endproc
