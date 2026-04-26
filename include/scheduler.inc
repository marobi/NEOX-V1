; ============================================================
; scheduler.inc
; NEOX - scheduler API
; ============================================================

.ifndef __SCHEDULER_INC__
__SCHEDULER_INC__ = 1

.include "scheduler_defs.inc"

.import scheduler_init
.import scheduler_set_current_context
.import scheduler_create_process
.import sched_pick_next
.import sched_context_switch
.import sched_yield

.import current_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import sched_lock

.endif
