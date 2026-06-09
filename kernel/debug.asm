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

    ; Scheduler lock diagnostics.
    lda #DBG_OWNER_NONE
    sta sched_lock_owner
    stz sched_lock_phase
    stz sched_lock_depth
    stz sched_lock_underflow

    ; Lock/gate owners.
    lda #DBG_OWNER_NONE
    sta file_io_gate_owner
    sta proc_gate_owner
    sta rp_lock_owner

    ; Sleepable gate debug.
    stz file_io_gate_phase
    stz proc_gate_phase
    stz dbg_gate_wait_reason
    stz dbg_gate_wait_object

    ; Timer debug.
    lda #DBG_PID_NONE
    sta dbg_timer_pid
    sta dbg_timer_slot

    stz dbg_timer_until_lo
    stz dbg_timer_until_hi
    stz dbg_timer_now_lo
    stz dbg_timer_now_hi

; DEBUG-BEGIN: temporary IRQ preemption selection diagnostic init
    stz dbg_irq_preempt_count
    lda #DBG_PID_NONE
    sta dbg_irq_current_pid
    sta dbg_irq_selected_pid
    stz dbg_irq_saved_sp
    stz dbg_irq_loaded_sp
; DEBUG-END: temporary IRQ preemption selection diagnostic init

    rts
.endproc