; ============================================================
; debug.asm
; NEOX - debug initialization helpers
;
; Purpose:
;   Initializes RP-visible debug state.
;
; Important:
;   This module does not own debug storage.
;   All debug variables live in shared_state.asm so the RP monitor
;   can continue reading the shared-state layout directly.
;
; Rule:
;   Debug fields are diagnostics only.
;   They must never be used as temporary scratch required for
;   correctness.
; ============================================================

.setcpu "65C02"

.include "debug.inc"

.segment "KERN_TEXT"

.export debug_init

; ------------------------------------------------------------
; debug_init
;
; Purpose:
;   Initialize monitor-visible debug state to deterministic values.
;
; Storage:
;   All variables initialized here are defined in shared_state.asm.
; ------------------------------------------------------------

.proc debug_init
    ; Legacy scheduler debug.
    stz sched_debug_marker
    stz sched_debug_pid

    lda #DBG_PID_NONE
    sta sched_debug_old_pid
    sta sched_debug_state_pid

    stz sched_debug_old_state
    stz sched_debug_state_old
    stz sched_debug_state_new

    ; Explicit scheduler debug.
    stz dbg_sched_path

    lda #DBG_PID_NONE
    sta dbg_sched_current_pid
    sta dbg_sched_selected_pid
    sta dbg_sched_saved_pid
    sta dbg_sched_loaded_pid
    sta dbg_sched_resume_pid

    stz dbg_sched_saved_sp
    stz dbg_sched_saved_mode

    stz dbg_sched_loaded_sp
    stz dbg_sched_resume_mode
    stz dbg_sched_resume_context

    ; Explicit process-state debug.
    lda #DBG_PID_NONE
    sta dbg_proc_state_pid

    stz dbg_proc_state_old
    stz dbg_proc_state_new

    ; Lock owners.
    lda #DBG_OWNER_NONE
    sta ksys_io_owner
    sta fd_lock_owner
    sta pipe_lock_owner
    sta rp_lock_owner

    ; Ksys I/O debug.
    stz ksys_io_phase
    stz dbg_io_wait_reason
    stz dbg_io_wait_object

    ; Timer debug.
    lda #DBG_PID_NONE
    sta dbg_timer_pid
    sta dbg_timer_slot

    stz dbg_timer_until_lo
    stz dbg_timer_until_hi
    stz dbg_timer_now_lo
    stz dbg_timer_now_hi

    rts
.endproc