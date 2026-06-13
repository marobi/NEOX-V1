; ============================================================
; sched_lock.inc
; NEOX - public scheduler-lock interface
;
; Purpose:
;   Provides callable scheduler-lock imports and shared lock-state
;   imports used by scheduler initialization/diagnostics.
;
; Rule:
;   All exits, including final context handoff after the target
;   private stack is installed, use jsr sched_lock_leave.
; ============================================================

.ifndef __SCHED_LOCK_INC__
__SCHED_LOCK_INC__ = 1

.import sched_lock_try_enter
.import sched_lock_leave

.import sched_lock
.import sched_lock_owner
.import sched_lock_phase
.import sched_lock_depth
.import sched_lock_underflow

SCHED_LOCK_BIT = $01

.endif ; __SCHED_LOCK_INC__
