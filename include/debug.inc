; ============================================================
; debug.inc
; NEOX - kernel debug constants and shared debug imports
; ============================================================

.ifndef NEOX_DEBUG_INC
.define NEOX_DEBUG_INC

DBG_PID_NONE        = $ff
DBG_OWNER_NONE      = $ff

DBG_MODE_NONE       = $00
DBG_MODE_IRQ_RTI    = $01
DBG_MODE_YIELD_RTI  = $02
DBG_MODE_BOOT       = $03

DBG_PATH_NONE       = $00
DBG_PATH_IRQ        = $01
DBG_PATH_YIELD      = $02

DBG_MARK_NONE       = $00

DBG_MARK_IRQ_ENTRY  = $01
DBG_MARK_IRQ_SAVE   = $02
DBG_MARK_PICK       = $03
DBG_MARK_YIELD      = $04
DBG_MARK_SELECTED   = $61
DBG_MARK_STACK_LOAD = $62
DBG_MARK_RESUME_RTI = $63
DBG_MARK_RESUME_BOOT = $64
DBG_MARK_STALE_RUN  = $ee

DBG_MARK_SCHED_LOCK_UNDERFLOW = $d7
DBG_MARK_SCHED_LOCK_OVERFLOW  = $d8

DBG_SCHED_LOCK_IDLE     = $00
DBG_SCHED_LOCK_ENTER    = $01
DBG_SCHED_LOCK_NESTED   = $02
DBG_SCHED_LOCK_LEAVE    = $03
DBG_SCHED_LOCK_BAD_LEAVE = $04

DBG_MARK_GATE_RECURSE = $e1
DBG_MARK_GATE_RELEASE = $e2

; File I/O gate phase values.
DBG_FILE_IO_IDLE        = $00

DBG_FILE_IO_READ_ACQ    = $11
DBG_FILE_IO_READ_CALL   = $12
DBG_FILE_IO_READ_RET    = $13
DBG_FILE_IO_READ_REL    = $14
DBG_FILE_IO_FD_READ_ENTER = $15
DBG_FILE_IO_FD_READ_PIPE  = $16
DBG_FILE_IO_FD_READ_DEV   = $17
DBG_FILE_IO_FD_READ_LOOKUP_CALL = $19
DBG_FILE_IO_FD_READ_LOOKUP_RET  = $1a
DBG_FILE_IO_FD_READ_PERM_CALL   = $1b
DBG_FILE_IO_FD_READ_PERM_RET    = $1c
DBG_FILE_IO_FD_READ_TYPE        = $1d
DBG_FILE_IO_READ_ACQ_FAIL = $1f

DBG_FILE_IO_WRITE_ACQ   = $21
DBG_FILE_IO_WRITE_CALL  = $22
DBG_FILE_IO_WRITE_RET   = $23
DBG_FILE_IO_WRITE_REL   = $24
DBG_FILE_IO_WRITE_ACQ_FAIL = $2f

DBG_FILE_IO_CLOSE_ACQ   = $31
DBG_FILE_IO_CLOSE_ACQ_FAIL = $3f
DBG_FILE_IO_DUP_ACQ     = $41
DBG_FILE_IO_DUP_ACQ_FAIL = $4f
DBG_FILE_IO_DUP2_ACQ    = $51
DBG_FILE_IO_DUP2_ACQ_FAIL = $5f
DBG_FILE_IO_PIPE_ACQ    = $61
DBG_FILE_IO_PIPE_ACQ_FAIL = $6f
DBG_FILE_IO_PIPE_LINK_ACQ = $71
DBG_FILE_IO_PIPE_LINK_ACQ_FAIL = $7f
DBG_FILE_IO_PROC_TERM_ACQ = $81
DBG_FILE_IO_PROC_TERM_ACQ_FAIL = $8f

DBG_PROC_GATE_IDLE      = $00

; temporary IRQ preemption skip diagnostic
DBG_IRQ_SKIP_NONE    = $00
DBG_IRQ_SKIP_MONITOR = $01
DBG_IRQ_SKIP_SCHED   = $02
DBG_IRQ_SKIP_RP      = $03
DBG_IRQ_SKIP_FILEIO  = $04
DBG_IRQ_SKIP_PROC    = $05
DBG_IRQ_ENTER_SWITCH = $06

; Legacy scheduler debug fields.
.import sched_debug_marker
.import sched_debug_pid
.import sched_debug_old_pid
.import sched_debug_old_state
.import sched_debug_state_pid
.import sched_debug_state_old
.import sched_debug_state_new

; Explicit scheduler debug fields.
.import dbg_sched_path
.import dbg_sched_current_pid
.import dbg_sched_selected_pid
.import dbg_sched_saved_pid
.import dbg_sched_saved_sp
.import dbg_sched_saved_mode
.import dbg_sched_loaded_pid
.import dbg_sched_loaded_sp
.import dbg_sched_resume_mode
.import dbg_sched_resume_pid
.import dbg_sched_resume_context

; Explicit process-state debug fields.
.import dbg_proc_state_pid
.import dbg_proc_state_old
.import dbg_proc_state_new

; Scheduler-lock debug fields.
.import sched_lock_owner
.import sched_lock_phase
.import sched_lock_depth
.import sched_lock_underflow

; Lock/gate owner debug fields.
.import file_io_gate_owner
.import file_io_gate_phase
.import proc_gate_owner
.import proc_gate_phase
.import rp_lock_owner

; Sleepable gate wait debug fields.
.import dbg_gate_wait_reason
.import dbg_gate_wait_object

; Timer debug fields.
.import dbg_timer_pid
.import dbg_timer_slot
.import dbg_timer_until_lo
.import dbg_timer_until_hi
.import dbg_timer_now_lo
.import dbg_timer_now_hi

; DEBUG-BEGIN: temporary IRQ preemption selection diagnostic imports
.import dbg_irq_preempt_count
.import dbg_irq_current_pid
.import dbg_irq_selected_pid
.import dbg_irq_saved_sp
.import dbg_irq_loaded_sp
.import dbg_irq_skip_reason
; DEBUG-END: temporary IRQ preemption selection diagnostic imports

.endif
