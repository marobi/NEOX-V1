; ============================================================
; sched_lock.inc
; NEOX - public scheduler-lock interface
;
; Purpose:
;   Provides callable scheduler-lock imports plus the one inline
;   final-handoff release macro that must be visible to scheduler.asm
;   at assembly time.
;
; Rule:
;   Normal exits use jsr sched_lock_leave.
;   Final BIOS context handoff uses SCHED_HANDOFF_RELEASE because
;   the handoff boundary has a strict A/X/Y register ABI.
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

; ------------------------------------------------------------
; SCHED_HANDOFF_RELEASE
;
; Inline-only final scheduler unlock used immediately before the
; BIOS context handoff. Do not replace this with jsr
; sched_lock_leave: the final handoff path has a strict A/X/Y BIOS
; register ABI and must keep the register setup explicit.
;
; This macro is for final handoff paths only. Normal scheduler
; critical-section exits must use sched_lock_leave.
;
; Requires debug.inc to define DBG_OWNER_NONE before expansion.
; ------------------------------------------------------------
.macro SCHED_HANDOFF_RELEASE
    ; IRQ must stay masked until BIOS_CONTEXT_RTI restores the
    ; selected task P, or until BIOS_CONTEXT_JUMP transfers into the
    ; selected context.
    sei

    lda sched_lock
    and #SCHED_LOCK_BIT
    bne :+
    inc sched_lock_underflow
:
    lda #SCHED_LOCK_BIT
    trb sched_lock
    lda #DBG_OWNER_NONE
    sta sched_lock_owner
    stz sched_lock_phase
    stz sched_lock_depth
.endmacro

.endif ; __SCHED_LOCK_INC__
