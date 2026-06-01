; ============================================================
; debug.inc
; NEOX - kernel debug constants and shared debug imports
;
; Purpose:
;   Common debug constants and imports for RP-visible debug
;   state stored in shared_state.asm.
;
; Rule:
;   Debug fields are diagnostics only.
;   They must never be used as temporary scratch required for
;   correctness.
; ============================================================

.ifndef NEOX_DEBUG_INC
.define NEOX_DEBUG_INC

; ------------------------------------------------------------
; Common debug constants
; ------------------------------------------------------------

DBG_PID_NONE        = $ff
DBG_OWNER_NONE      = $ff

DBG_MODE_NONE       = $00
DBG_MODE_IRQ_RTI    = $01
DBG_MODE_YIELD_RTS  = $02

DBG_PATH_NONE       = $00
DBG_PATH_IRQ        = $01
DBG_PATH_YIELD      = $02

; ------------------------------------------------------------
; Scheduler marker values
; ------------------------------------------------------------

DBG_MARK_NONE       = $00

DBG_MARK_IRQ_ENTRY  = $01
DBG_MARK_IRQ_SAVE   = $02
DBG_MARK_PICK       = $03
DBG_MARK_YIELD      = $04
DBG_MARK_SELECTED   = $61
DBG_MARK_STACK_LOAD = $62
DBG_MARK_RESUME_RTI = $63
DBG_MARK_RESUME_RTS = $64
DBG_MARK_STALE_RUN  = $ee

DBG_MARK_KIO_RECURSE = $e1

; ------------------------------------------------------------
; Ksys I/O phase values
; ------------------------------------------------------------

DBG_KIO_IDLE        = $00

DBG_KIO_READ_ACQ    = $11
DBG_KIO_READ_CALL   = $12
DBG_KIO_READ_RET    = $13
DBG_KIO_READ_REL    = $14

DBG_KIO_WRITE_ACQ   = $21
DBG_KIO_WRITE_CALL  = $22
DBG_KIO_WRITE_RET   = $23
DBG_KIO_WRITE_REL   = $24

; ------------------------------------------------------------
; Legacy scheduler debug fields
;
; Storage is in shared_state.asm.
; Kept for current monitor / ps output.
; ------------------------------------------------------------

.import sched_debug_marker
.import sched_debug_pid

.import sched_debug_old_pid
.import sched_debug_old_state

.import sched_debug_state_pid
.import sched_debug_state_old
.import sched_debug_state_new

; ------------------------------------------------------------
; Explicit scheduler debug fields
;
; Storage is in shared_state.asm.
; ------------------------------------------------------------

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

; ------------------------------------------------------------
; Explicit process-state debug fields
;
; These may alias the legacy sched_debug_state_* fields or be
; separate storage, depending on shared_state.asm.
; ------------------------------------------------------------

.import dbg_proc_state_pid
.import dbg_proc_state_old
.import dbg_proc_state_new

; ------------------------------------------------------------
; Lock owner debug fields
;
; Storage is in shared_state.asm.
; These are monitor-visible owner bytes only.
; The actual lock bytes remain separate:
;   ksys_io_lock
;   fd_lock
;   pipe_lock
;   rp_lock
; ------------------------------------------------------------

.import ksys_io_owner
.import fd_lock_owner
.import pipe_lock_owner
.import rp_lock_owner

; ------------------------------------------------------------
; Ksys I/O debug fields
; ------------------------------------------------------------

.import ksys_io_phase

.import dbg_io_wait_reason
.import dbg_io_wait_object

; ------------------------------------------------------------
; Timer debug fields
; ------------------------------------------------------------

.import dbg_timer_pid
.import dbg_timer_slot
.import dbg_timer_until_lo
.import dbg_timer_until_hi
.import dbg_timer_now_lo
.import dbg_timer_now_hi

.endif
