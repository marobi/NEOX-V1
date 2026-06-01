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
;   1. Save A/X/Y onto the interrupted context stack
;   2. Ask IRQ classification logic for the source
;   3. If source = monitor request:
;        -> acknowledge it
;        -> set monitor_pending
;        -> restore interrupted context
;   4. If source = timer tick:
;        -> if sched_lock != 0, resume interrupted context
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
;   Monitor entry is deferred.
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "mailbox.inc"

.export irq_entry
.export nmi_entry

.import brk_vector

.import scheduler_irq_tick
.import sched_context_switch
.import sched_lock
.import monitor_pending
.import console_owner_pid

.import ksys_io_lock
.import fd_lock
.import pipe_lock
.import rp_lock

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
;   - records a pending monitor request and RTI
;   - or transfers to scheduler switch logic
;
; Clobbers:
;   A, X, Y
;
; Notes:
;   The interrupted context is preserved on its private stack
;   until a dispatch decision is made.
; ------------------------------------------------------------

.proc irq_entry
    pha
    phx
    phy

    lda RP_IRQ_SOURCE
;	jsr BIOS_ACQ_IRQ			; ack IRQ
	stz RP_IRQ_SOURCE
	
	cmp #RP_IRQ_SRC_NONE		; non IRQ
	beq irq_restore

    cmp #RP_IRQ_SRC_TIMER		; TIMER IRQ
    beq @timer

    cmp #RP_IRQ_SRC_MONITOR		; MONITOR IRQ
    beq @monitor

    tsx
    lda $0104,x
    and #$10
    bne brk_entry				; BREAK

    ; unknown → just return
    bra irq_restore

@monitor:	
    lda #1
	sta monitor_pending
	bra irq_restore

@timer:
    ; Count every hardware timer IRQ, even when this is not a
    ; safe preemption point.
    jsr scheduler_irq_tick

    ; Only context-switch when no scheduler/subsystem lock is held.
    lda sched_lock
    ora ksys_io_lock
    ora fd_lock
    ora pipe_lock
    ora rp_lock
    bne irq_restore

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
	; TODO: we need to set the context = 0
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
