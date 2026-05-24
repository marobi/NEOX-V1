; ============================================================
; shared_state.asm
; NEOX - shared kernel-visible writable state
;
; Purpose:
;   Defines all writable state that must be visible identically
;   in every MMU context.
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "fd.inc"
.include "timer.inc"
.include "pipe.inc"

.segment "KERN_BSS"

; ------------------------------------------------------------
;
; ------------------------------------------------------------
.export kernel_version
.export brk_vector

kernel_version:	.res 2
brk_vector:		.res 2

; ------------------------------------------------------------
;
; ------------------------------------------------------------

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

rp_lock:        .res 1

; ============================================================
; other lock definitions
;	
.export fd_lock

fd_lock:
    .res 1

; ------------------------------------------------------------
; ksys_io_lock
;
; Purpose:
;   Global serialization owner for ksys_read / ksys_write.
;
; Policy:
;   Only one process may execute the read/write syscall path at
;   a time.
;
;   This covers:
;     - syscall argument decoding
;     - io_ptr backend buffer pointer
;     - fd_read / fd_write
;     - FD dispatch to pipe, console, and future file/device
;
; Wait rule:
;   A process that cannot acquire this lock must not spin.
;   It blocks on:
;
;       WAIT_KSYS_IO, object 0
;
;   and calls sched_yield.
; ------------------------------------------------------------

.export ksys_io_lock

ksys_io_lock:
    .res 1
	
; ------------------------------------------------------------
; Scheduler core state
;
; current_pid:
;   PID of the currently active context.
;
; proc_state[pid]:
;   Process lifecycle / scheduler state:
;     PROC_EMPTY
;     PROC_NEW
;     PROC_READY
;     PROC_RUNNING
;
; proc_context[pid]:
;   MMU context number associated with each process.
;
; proc_sp[pid]:
;   Saved stack pointer for processes that have already executed
;   and have been preempted at least once.
;
; proc_entryL/H[pid]:
;   First-entry address for PROC_NEW tasks.
;
; proc_flags[pid]:
;   Process characteristics flags:
;    PROC_FLAG_MONITOR
;    PROC_FLAG_SYSTEM
;
; sched_lock:
;   Simple preemption guard.
;   When nonzero, irq_entry restores the interrupted context
;   unchanged instead of invoking sched_context_switch.
; ------------------------------------------------------------

.export current_pid
.export proc_state
.export proc_context
.export proc_sp
.export proc_entryL
.export proc_entryH
.export proc_flags
.export proc_resume_mode
.export proc_parent_pid

current_pid:    .res 1
proc_state:     .res MAX_PROCS
proc_context:   .res MAX_PROCS
proc_sp:        .res MAX_PROCS
proc_entryL:    .res MAX_PROCS
proc_entryH:    .res MAX_PROCS
proc_flags:		.res MAX_PROCS
proc_resume_mode:
				.res MAX_PROCS

; ------------------------------------------------------------
; Parent PID table
;
; proc_parent_pid[pid] =
;   PID of creator/owner process
;
; $FF = no parent / kernel-owned
; ------------------------------------------------------------

proc_parent_pid:
    .res MAX_PROCS

.export proc_signal_pending

proc_signal_pending:
    .res MAX_PROCS
	
; ------------------------------------------------------------
;
; ------------------------------------------------------------
.export sched_lock
.export console_owner_pid
.export monitor_active
.export monitor_pending

sched_lock:     .res 1

; ------------------------------------------------------------
; console_owner_pid
;
; Purpose:
;   Identifies which context currently owns console input.
;
; Policy:
;   - 0  => MICMON / supervisor owns the console
;   - >0 => foreground task owns the console
; ------------------------------------------------------------

console_owner_pid:   .res 1

monitor_active:		 .res 1

monitor_pending:	 .res 1

; ------------------------------------------------------------
; Per-process file descriptor tables
;
; Each process owns a small fixed FD table.
; Entry contains:
;   - object index into open-object table
;   - per-FD flags (read/write/close-on-exec)
;
; Layout:
;   proc_fd_obj[pid * MAX_FDS + fd]
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
;   type     - object type (device/file/pipe)
;   refcnt   - number of FDs referencing this object
;   flags    - object-level flags (future use)
;   dev      - backend device id (console for now)
;
; Notes:
;   Multiple FDs (even from different processes) may refer to
;   the same open object. Refcount tracks lifetime.
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
;   WAIT_NONE, WAIT_CONSOLE, WAIT_DEVICE, ...
;
; wait_object[pid]:
;   reason-specific object id.
;   For WAIT_CONSOLE this is currently 0.
; ------------------------------------------------------------

.export wait_reason
.export wait_object

wait_reason:
    .res MAX_PROCS

wait_object:
    .res MAX_PROCS

;
;
;
.export proc_exit_code

proc_exit_code:
    .res MAX_PROCS


; ------------------------------------------------------------
; Global scheduler tick counter
;
; Incremented once per timer IRQ.
;
; 16-bit:
;   ~21.8 minutes at 50 Hz.
; ------------------------------------------------------------

.export system_ticks_lo
.export system_ticks_hi

system_ticks_lo:   .res 1
system_ticks_hi:   .res 1

; ------------------------------------------------------------
; Active timer wait table
;
; timer_pid[slot]:
;   PID waiting on this timer slot.
;
;   TIMER_NONE = unused slot
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

; ============================================================
; Process runtime accounting
;
; Updated from timer IRQ context.
;
; proc_ticks_*:
;   Per-process scheduled runtime in timer ticks.
;
; Counters are 16-bit and naturally wrap.
; ============================================================

.export proc_ticks_lo
.export proc_ticks_hi

proc_ticks_lo:    .res MAX_PROCS
proc_ticks_hi:    .res MAX_PROCS

.export console_read_len_lo
.export console_read_len_hi

console_read_len_lo: .res 1
console_read_len_hi: .res 1

; ------------------------------------------------------------
;
; ------------------------------------------------------------

.export init_task_count
.export init_task_ptr

init_task_count:
    .res 1

init_task_ptr:
    .res 2

; ------------------------------------------------------------
; Pipes
; ------------------------------------------------------------

.export pipe_lock
.export pipe_state
.export pipe_head
.export pipe_tail
.export pipe_count
.export pipe_readers
.export pipe_writers
.export pipe_buf

.export open_pipe
.export open_pipe_mode

; ============================================================
; Pipe state
;
; pipe_lock is a shared-memory lock byte.
; Do not place it in zero page.
; ============================================================

pipe_lock:          .res 1

pipe_state:         .res MAX_PIPES
pipe_head:          .res MAX_PIPES
pipe_tail:          .res MAX_PIPES
pipe_count:         .res MAX_PIPES
pipe_readers:       .res MAX_PIPES
pipe_writers:       .res MAX_PIPES

; PIPE_MAX * PIPE_BUF_SIZE = 8 * 64 = 512 bytes
pipe_buf:           .res MAX_PIPES * PIPE_BUF_SIZE

; Per-open-object pipe endpoint metadata.
; Indexed by open object number.
open_pipe:          .res OPEN_MAX
open_pipe_mode:     .res OPEN_MAX

;
;
;
.export sched_ticks_lo
.export sched_ticks_hi

sched_ticks_lo:
    .res 1

sched_ticks_hi:
    .res 1

; ------------------------------------------------------------

.export ksys_io_owner
.export fd_lock_owner

ksys_io_owner:
    .res 1

fd_lock_owner:
    .res 1
	
; ------------------------------------------------------------
; Scheduler debug markers
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
