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
;
;   Sleepable gates do not suppress timer preemption. Gate ownership is
;   tracked by PID and remains valid while another process runs.
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
.include "process.inc"
.include "scheduler_defs.inc"
.include "signal.inc"

.export irq_entry
.export nmi_entry

.import brk_vector

.import supervisor_enter_from_irq

.import scheduler_irq_tick
.import sched_context_switch
.import sched_lock
.import monitor_active
.import console_owner_pid
.import proc_signal_pending

.import rp_lock

.import file_io_gate_owner
.import proc_state
.import wait_reason
.import proc_wake

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
    beq :+
    jmp brk_entry                  ; BREAK
:

    lda RP_IRQ_SOURCE
    jsr BIOS_ACK_IRQ               ; ack IRQ

    cmp #RP_IRQ_SRC_NONE           ; non IRQ
    bne :+
    jmp irq_restore
:

    cmp #RP_IRQ_SRC_TIMER          ; TIMER IRQ
    bne :+
    jmp @timer
:

    cmp #RP_IRQ_SRC_MONITOR        ; MONITOR IRQ
    bne :+
    jmp @monitor
:

    cmp #RP_IRQ_SRC_FS_DONE        ; RP filesystem completion
    bne :+
    jmp @fs_done
:

    cmp #RP_IRQ_SRC_CONSOLE_BREAK  ; foreground console interrupt
    bne :+
    jmp @console_break
:

    ; unknown -> just return
    jmp irq_restore

@monitor:
    jmp supervisor_enter_from_irq	; must be JMP

@console_break:
    ; MICMON is a freeze-style supervisor and is explicitly excluded from
    ; NEOX foreground process interruption.
    lda monitor_active
    bne irq_restore

    ; The current RP console focus is synchronized into console_owner_pid by
    ; the scheduler. Only normal live process PIDs may receive SIG_INT.
    ldx console_owner_pid
    cpx #FIRST_TASK_PID
    bcc irq_restore
    cpx #MAX_PROCS
    bcs irq_restore

    lda proc_state,x
    cmp #PROC_EMPTY
    beq irq_restore
    cmp #PROC_ZOMBIE
    beq irq_restore

    lda #SIG_INT
    sta proc_signal_pending,x

    ; Do not enter the scheduler through an already active handoff or short
    ; RP critical section. The pending signal remains recorded and will be
    ; applied at the next safe scheduler pass.
    lda sched_lock
    ora rp_lock
    bne irq_restore

    jmp sched_context_switch

@fs_done:
    ; The FILE_IO gate owner is the sole possible generic filesystem
    ; request owner. Wake it only when the recorded process state still
    ; matches an active WAIT_RP transaction. The owner itself will read
    ; the mailbox result and release FILE_IO after resuming.
    ldx file_io_gate_owner
    cpx #GATE_OWNER_NONE
    beq irq_restore

    cpx #MAX_PROCS
    bcs irq_restore

    lda proc_state,x
    cmp #PROC_BLOCKED
    bne irq_restore

    lda wait_reason,x
    cmp #WAIT_RP
    bne irq_restore

    jsr proc_wake

    ; MICMON remains a freeze-style supervisor. Keep the owner READY but
    ; do not leave the monitor through a filesystem completion interrupt.
    lda monitor_active
    bne irq_restore

    ; A completion IRQ does not advance ticks. If a short scheduler or
    ; mailbox critical section is active, leave the owner READY and let
    ; the next scheduling opportunity select it.
    lda sched_lock
    ora rp_lock
    bne irq_restore

    jmp sched_context_switch
	
@timer:
    ; Freeze-style monitor:
    ; timer IRQs are already acknowledged by BIOS_ACK_IRQ before
    ; reaching this branch. While MICMON is active, do not advance
    ; system_ticks and do not run scheduler tick accounting.
    lda monitor_active
    bne irq_restore

    ; Count every hardware timer IRQ outside monitor mode.
    jsr scheduler_irq_tick

    ; sched_lock protects the scheduler handoff itself. rp_lock remains a
    ; short non-sleeping mailbox lock until the generic RP request path
    ; replaces it. Sleepable FILE_IO/PROC gates deliberately do not block
    ; timer preemption: another process may run, but cannot enter the same
    ; protected subsystem until the owning PID releases its gate.
    lda sched_lock
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
