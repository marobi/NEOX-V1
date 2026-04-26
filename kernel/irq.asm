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
;        -> enter supervisor context 0
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
;   So sched_context_switch / enter_monitor_irq may later
;   restore with:
;       PLY / PLX / PLA / RTI
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "mailbox.inc"

.export irq_entry
.export nmi_entry
.export irq_get_source

.import brk_vector

.import sched_context_switch
.import sched_lock
.import enter_monitor_irq
.import console_owner_pid

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
;   Either:
;     - restores interrupted context and RTI
;     - enters monitor
;     - or transfers to scheduler switch logic
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

    jsr irq_get_source

    cmp #RP_IRQ_SRC_MONITOR
    beq @monitor

    cmp #RP_IRQ_SRC_TIMER
    beq @timer

    tsx
    lda $0104,x
    and #$10
    bne brk_entry

    ; unknown → just return
    bra irq_restore

@monitor:
    jsr BIOS_ACK_IRQ         ; clear source
    jmp enter_monitor_irq

@timer:
    jsr BIOS_ACK_IRQ        ; clear source

    lda sched_lock
    bne irq_restore

    jmp sched_context_switch
.endproc

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

; ============================================================
; irq_get_source
;
; Purpose:
;   Read IRQ source provided by RP2350.
;
; Returns:
;   A = RP_IRQ_SOURCE_XXXX
;
; Notes:
;   RP2350 must set RP_IRQ_SOURCE before raising IRQ.
; ============================================================

.proc irq_get_source
    lda RP_IRQ_SOURCE
    rts
.endproc