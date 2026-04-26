; ============================================================
; sched_lock.asm
; NEOX - scheduler preemption guard helpers
;
; Purpose:
;   Provides the small helper routines used to prevent timer-IRQ
;   driven preemption while the kernel is inside a critical
;   section.
;
; Architecture:
;   - Single 6502 CPU
;   - Preemption source is timer IRQ
;   - No true parallel execution on the 6502 side
;
; Design:
;   - sched_lock is a shared byte in KERN_BSS
;   - irq_entry checks sched_lock before calling scheduler
;   - nonzero sched_lock means:
;       "restore interrupted context unchanged"
;
; Important:
;   This is not a general mutual-exclusion primitive.
;   It is a simple preemption guard used to defer scheduling
;   while kernel state is being updated.
;
; Usage rule:
;   Every sched_lock_enter must be balanced by a corresponding
;   sched_lock_leave on all exit paths.
; ============================================================

.setcpu "65C02"

.export sched_lock_enter
.export sched_lock_leave

.import sched_lock

.segment "KERN_TEXT"

; ------------------------------------------------------------
; sched_lock_enter
;
; Purpose:
;   Enter a scheduler-critical section.
;
; Inputs:
;   None.
;
; Outputs:
;   None.
;
; Clobbers:
;   None.
;
; Behavior:
;   Increments the shared sched_lock counter.
;
; Notes:
;   Nested use is allowed as long as each enter is matched by
;   a leave. irq_entry treats any nonzero value as "do not
;   schedule now".
; ------------------------------------------------------------

.proc sched_lock_enter
    inc sched_lock
    rts
.endproc

; ------------------------------------------------------------
; sched_lock_leave
;
; Purpose:
;   Leave a scheduler-critical section.
;
; Inputs:
;   None.
;
; Outputs:
;   None.
;
; Clobbers:
;   None.
;
; Behavior:
;   Decrements the shared sched_lock counter.
;
; Notes:
;   Caller must guarantee balanced use. This routine does not
;   attempt to detect underflow.
; ------------------------------------------------------------

.proc sched_lock_leave
    dec sched_lock
    rts
.endproc
