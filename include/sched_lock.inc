; ============================================================
; sched_lock.inc
; NEOX - public scheduler-lock interface
;
; Purpose:
;   Provides the callable scheduler-lock interface and real guard byte.
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

SCHED_LOCK_BIT = $01

.endif ; __SCHED_LOCK_INC__
