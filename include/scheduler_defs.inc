; ============================================================
; scheduler_defs.inc
; NEOX - scheduler constants
; ============================================================

.ifndef __SCHEDULER_DEFS_INC__
__SCHEDULER_DEFS_INC__ = 1

MAX_PROCS      = 4
FIRST_TASK_PID = 1

.struct proc_create_args
	context			.byte
	reserved		.byte
	entry			.word
.endstruct

PROC_CREATE_ARGS_SIZE = .sizeof(proc_create_args)

.endif
