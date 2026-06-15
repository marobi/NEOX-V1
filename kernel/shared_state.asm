; ============================================================
; shared_state.asm
; NEOX - shared kernel-visible writable state
;
; Purpose:
;   Defines all writable state that must be visible identically
;   in every MMU context.
;
; Notes:
;   This file owns:
;     - real shared kernel state
;     - RP/monitor-visible process tables
;     - RP/monitor-visible lock/debug state
;
;   Debug fields stay here intentionally because the RP monitor
;   reads shared kernel state directly.
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "fd.inc"
.include "timer.inc"
.include "pipe.inc"

.segment "KERN_BSS"

; ------------------------------------------------------------
; Kernel metadata
; ------------------------------------------------------------

.export kernel_version
.export brk_vector

kernel_version:
    .res 2

brk_vector:
    .res 2

; ------------------------------------------------------------
; RP2350 mailbox serialization lock
;
; Purpose:
;   Ensures only one kernel-side mailbox transaction is active
;   at a time.
;
; Notes:
;   This is shared state because the mailbox hardware and request
;   block are global resources, not per-process resources.
; ------------------------------------------------------------

.export rp_lock

rp_lock:
    .res 1

; ------------------------------------------------------------
; File I/O syscall serialization gate
;
; Purpose:
;   Serializes FD/open-object/pipe/console syscall paths:
;     read, write, close, pipe, dup, dup2.
;
; Policy:
;   This is a sleepable gate, not an IRQ-preemption blocker.
;   It must not be held across sched_yield. A syscall that must
;   block releases the gate, sets WAIT_LOCK / LOCK_ID_FILE_IO,
;   yields, and retries.
;
; FIFO queue:
;   file_io_gate_wait_head / tail hold waiting PIDs or $FF.
;   file_io_gate_next[pid] links waiting PIDs.
; ------------------------------------------------------------

.export file_io_gate
.export file_io_gate_owner
.export file_io_gate_phase
.export file_io_gate_wait_head
.export file_io_gate_wait_tail
.export file_io_gate_next

.export proc_gate
.export proc_gate_owner
.export proc_gate_phase
.export proc_gate_wait_head
.export proc_gate_wait_tail
.export proc_gate_next

file_io_gate:
    .res 1

file_io_gate_owner:
    .res 1

file_io_gate_phase:
    .res 1

file_io_gate_wait_head:
    .res 1

file_io_gate_wait_tail:
    .res 1

file_io_gate_next:
    .res MAX_PROCS

; Future process-management syscall gate.
; The state is present now so the same generated gate primitive can
; be build-tested before process syscalls are routed through it.

proc_gate:
    .res 1

proc_gate_owner:
    .res 1

proc_gate_phase:
    .res 1

proc_gate_wait_head:
    .res 1

proc_gate_wait_tail:
    .res 1

proc_gate_next:
    .res MAX_PROCS

; ------------------------------------------------------------
; Scheduler core state
;
; active_pid:
;   PID whose CPU/MMU context is actually executing.
;
; sched_cursor_pid:
;   Scheduler-local round-robin cursor / last selected PID.
;   It must not be used as caller identity.
;
; proc_state[pid]:
;   Process lifecycle / scheduler state:
;     PROC_EMPTY
;     PROC_NEW
;     PROC_READY
;     PROC_RUNNING
;     PROC_BLOCKED
;
; proc_context[pid]:
;   MMU context number associated with each process.
;
; proc_sp[pid]:
;   Saved stack pointer for processes that have already executed
;   and have been preempted/yielded at least once.
;
; proc_entryL/H[pid]:
;   First-entry address for PROC_NEW tasks.
;
; proc_flags[pid]:
;   Process characteristics flags.
;
; proc_parent_pid[pid]:
;   PID of creator/owner process.
;   $FF = no parent / kernel-owned.
; ------------------------------------------------------------

.export active_pid
.export sched_cursor_pid
.export proc_state
.export proc_context
.export proc_sp
.export proc_entryL
.export proc_entryH
.export proc_flags
.export proc_parent_pid
.export proc_signal_pending

active_pid:
    .res 1

sched_cursor_pid:
    .res 1

proc_state:
    .res MAX_PROCS

proc_context:
    .res MAX_PROCS

proc_sp:
    .res MAX_PROCS

proc_entryL:
    .res MAX_PROCS

proc_entryH:
    .res MAX_PROCS

proc_flags:
    .res MAX_PROCS

proc_parent_pid:
    .res MAX_PROCS

proc_signal_pending:
    .res MAX_PROCS

; ------------------------------------------------------------
; Scheduler / monitor state
;
; sched_lock:
;   Non-sleeping scheduler preemption guard. Bit 0 is acquired with
;   W65C02 TSB by sched_lock_try_enter and cleared with TRB by
;   sched_lock_leave.  Try-enter returns C clear only when this caller
;   acquired the bit; callers must not enter scheduler-critical code
;   or call leave when C is set.  This is not a FIFO gate and must
;   never block or yield.  It is deliberately non-recursive.
;
; sched_lock_owner / phase / depth / underflow:
;   Monitor-visible diagnostics for scheduler-lock correctness.
;   Owner is diagnostic only; scheduler handoff may enter in one
;   process/context and leave after another PID has been selected.
;   Depth is diagnostic only: 0 = unlocked, 1 = locked.
;
; console_owner_pid:
;   Identifies which process currently owns console input.
;   $FF = none / monitor-side default.
;
; monitor_active:
;   Nonzero while monitor mode is active.
;
; active_context:
;   Actual MMU context currently executing on the 6502.
;   This is paired with active_pid and changes only at the
;   final scheduler/context handoff boundary.
; ------------------------------------------------------------
; ------------------------------------------------------------

.export sched_lock
.export sched_lock_owner
.export sched_lock_phase
.export sched_lock_depth
.export sched_lock_underflow
.export console_owner_pid
.export monitor_active
.export active_context

sched_lock:
    .res 1

sched_lock_owner:
    .res 1

sched_lock_phase:
    .res 1

sched_lock_depth:
    .res 1

sched_lock_underflow:
    .res 1

console_owner_pid:
    .res 1

monitor_active:
    .res 1

active_context:
	.res 1
	
; ------------------------------------------------------------
; Per-process file descriptor tables
;
; Each process owns a fixed FD table.
;
; Layout:
;   proc_fd_obj[pid * MAX_FDS + fd]
;   proc_fd_flags[pid * MAX_FDS + fd]
; ------------------------------------------------------------

.export proc_fd_obj
.export proc_fd_flags

proc_fd_obj:
    .res MAX_PROCS * MAX_FDS

proc_fd_flags:
    .res MAX_PROCS * MAX_FDS

; ------------------------------------------------------------
; System-wide open object table
;
; Each entry represents a shared open resource.
;
; Fields:
;   open_type   - object type
;   open_refcnt - number of FDs referencing this object
;   open_flags  - object-level flags
;   open_dev    - backend device id for device objects
; ------------------------------------------------------------

.export open_type
.export open_refcnt
.export open_flags
.export open_dev

open_type:
    .res OPEN_MAX

open_refcnt:
    .res OPEN_MAX

open_flags:
    .res OPEN_MAX

open_dev:
    .res OPEN_MAX

; ------------------------------------------------------------
; Per-process wait state
;
; wait_reason[pid]:
;   WAIT_NONE, WAIT_CONSOLE, WAIT_DEVICE, WAIT_PIPE_READ,
;   WAIT_TIMER, WAIT_PROC, WAIT_LOCK, WAIT_PIPE_WRITE, ...
;   WAIT_PIPE remains a compatibility alias for WAIT_PIPE_READ.
;
; wait_object[pid]:
;   reason-specific object id. For WAIT_LOCK this is one of
;   LOCK_ID_FILE_IO / LOCK_ID_PROC.
; ------------------------------------------------------------

.export wait_reason
.export wait_object

wait_reason:
    .res MAX_PROCS

wait_object:
    .res MAX_PROCS

; ------------------------------------------------------------
; Per-process exit codes
; ------------------------------------------------------------

.export proc_exit_code

proc_exit_code:
    .res MAX_PROCS

; ------------------------------------------------------------
; Global scheduler tick counter
;
; Incremented once per timer IRQ.
;
; 16-bit:
;   naturally wraps.
; ------------------------------------------------------------

.export system_ticks_lo
.export system_ticks_hi

system_ticks_lo:
    .res 1

system_ticks_hi:
    .res 1

; ------------------------------------------------------------
; Active timer wait table
;
; timer_pid[slot]:
;   PID waiting on this timer slot.
;   TIMER_NONE = unused slot.
;
; timer_until_lo/hi[slot]:
;   Absolute wake tick.
;
; Notes:
;   wait_object[pid] stores the timer slot index while the
;   process is blocked on WAIT_TIMER.
; ------------------------------------------------------------

.export timer_pid
.export timer_until_lo
.export timer_until_hi

timer_pid:
    .res MAX_TIMER

timer_until_lo:
    .res MAX_TIMER

timer_until_hi:
    .res MAX_TIMER

; ------------------------------------------------------------
; Process runtime accounting
;
; Updated from timer IRQ context.
;
; proc_ticks_*:
;   Per-process scheduled runtime in timer ticks.
;
; Counters are 16-bit and naturally wrap.
; ------------------------------------------------------------

.export proc_ticks_lo
.export proc_ticks_hi

proc_ticks_lo:
    .res MAX_PROCS

proc_ticks_hi:
    .res MAX_PROCS

; ------------------------------------------------------------
; Console read state
; ------------------------------------------------------------

.export console_read_len_lo
.export console_read_len_hi

console_read_len_lo:
    .res 1

console_read_len_hi:
    .res 1

; ------------------------------------------------------------
; Init task table state
; ------------------------------------------------------------

.export init_task_count
.export init_task_ptr

init_task_count:
    .res 1

init_task_ptr:
    .res 2

; ------------------------------------------------------------
; Pipe state
;
; pipe_state/head/tail/count/readers/writers:
;   Pipe metadata indexed by pipe id.
;
; pipe_buf:
;   Pipe storage:
;     MAX_PIPES * PIPE_BUF_SIZE
;
; open_pipe/open_pipe_mode:
;   Per-open-object pipe endpoint metadata.
;   Indexed by open object number.
; ------------------------------------------------------------

.export pipe_state
.export pipe_head
.export pipe_tail
.export pipe_count
.export pipe_readers
.export pipe_writers
.export pipe_buf

.export open_pipe
.export open_pipe_mode

pipe_state:
    .res MAX_PIPES

pipe_head:
    .res MAX_PIPES

pipe_tail:
    .res MAX_PIPES

pipe_count:
    .res MAX_PIPES

pipe_readers:
    .res MAX_PIPES

pipe_writers:
    .res MAX_PIPES

pipe_buf:
    .res MAX_PIPES * PIPE_BUF_SIZE

open_pipe:
    .res OPEN_MAX

open_pipe_mode:
    .res OPEN_MAX

; ============================================================
; RP-visible debug state
;
; Important:
;   These fields are diagnostics only.
;   They must never be used as scratch required for
;   correctness.
;
;   They stay in shared_state.asm intentionally because the RP
;   monitor reads shared kernel state directly.
; ============================================================

; ------------------------------------------------------------
; Legacy scheduler debug markers
;
; Kept for existing monitor / ps output.
; ------------------------------------------------------------

.export sched_debug_marker
.export sched_debug_pid

sched_debug_marker:
    .res 1

sched_debug_pid:
    .res 1

.export sched_debug_old_pid
.export sched_debug_old_state

sched_debug_old_pid:
    .res 1

sched_debug_old_state:
    .res 1

.export sched_debug_state_pid
.export sched_debug_state_old
.export sched_debug_state_new

sched_debug_state_pid:
    .res 1

sched_debug_state_old:
    .res 1

sched_debug_state_new:
    .res 1

; ------------------------------------------------------------
; Explicit scheduler debug state
;
; These fields give unambiguous scheduler snapshots and should
; replace overloaded legacy debug bytes over time.
; ------------------------------------------------------------

.export dbg_sched_path
.export dbg_sched_current_pid
.export dbg_sched_selected_pid

dbg_sched_path:
    .res 1

dbg_sched_current_pid:
    .res 1

dbg_sched_selected_pid:
    .res 1

.export dbg_sched_saved_pid
.export dbg_sched_saved_sp
.export dbg_sched_saved_mode

dbg_sched_saved_pid:
    .res 1

dbg_sched_saved_sp:
    .res 1

dbg_sched_saved_mode:
    .res 1

.export dbg_sched_loaded_pid
.export dbg_sched_loaded_sp

dbg_sched_loaded_pid:
    .res 1

dbg_sched_loaded_sp:
    .res 1

.export dbg_sched_resume_mode
.export dbg_sched_resume_pid
.export dbg_sched_resume_context

dbg_sched_resume_mode:
    .res 1

dbg_sched_resume_pid:
    .res 1

dbg_sched_resume_context:
    .res 1

; ------------------------------------------------------------
; Explicit process-state debug fields
;
; These are separate from the legacy sched_debug_state_* fields.
; During migration, scheduler code may update both.
; ------------------------------------------------------------

.export dbg_proc_state_pid
.export dbg_proc_state_old
.export dbg_proc_state_new

dbg_proc_state_pid:
    .res 1

dbg_proc_state_old:
    .res 1

dbg_proc_state_new:
    .res 1

; ------------------------------------------------------------
; Lock owner debug fields
;
; $FF = no owner / lock is free.
;
; These fields are diagnostics only. They do not implement the
; locks themselves.
; ------------------------------------------------------------

.export rp_lock_owner

rp_lock_owner:
    .res 1

; ------------------------------------------------------------
; Sleepable gate debug fields
;
; file_io_gate_phase examples:
;   $00 = idle
;   $11 = read acquired
;   $12 = read calling fd/backend
;   $13 = read returned from fd/backend
;   $14 = read releasing
;   $21 = write acquired
;   $22 = write calling fd/backend
;   $23 = write returned from fd/backend
;   $24 = write releasing
; ------------------------------------------------------------

.export dbg_gate_wait_reason
.export dbg_gate_wait_object


dbg_gate_wait_reason:
    .res 1

dbg_gate_wait_object:
    .res 1

; ------------------------------------------------------------
; Timer debug fields
; ------------------------------------------------------------

.export dbg_timer_pid
.export dbg_timer_slot
.export dbg_timer_until_lo
.export dbg_timer_until_hi
.export dbg_timer_now_lo
.export dbg_timer_now_hi

dbg_timer_pid:
    .res 1

dbg_timer_slot:
    .res 1

dbg_timer_until_lo:
    .res 1

dbg_timer_until_hi:
    .res 1

dbg_timer_now_lo:
    .res 1

dbg_timer_now_hi:
    .res 1

.export dbg_irq_preempt_count
.export dbg_irq_current_pid
.export dbg_irq_selected_pid
.export dbg_irq_saved_sp
.export dbg_irq_loaded_sp
.export dbg_irq_skip_reason

dbg_irq_preempt_count: .res 1
dbg_irq_current_pid:   .res 1
dbg_irq_selected_pid:  .res 1
dbg_irq_saved_sp:      .res 1
dbg_irq_loaded_sp:     .res 1
dbg_irq_skip_reason:   .res 1




