; ============================================================
; timer.inc
; NEOX - scheduler timer wait definitions
;
; Purpose:
;   Defines the timer wait subsystem used by sys_sleep and
;   future timeout-based waits.
; ============================================================

.ifndef __TIMER_INC__
__TIMER_INC__ = 1

; ------------------------------------------------------------
; Maximum simultaneously active timer waits
; ------------------------------------------------------------

MAX_TIMER      = 8

; ------------------------------------------------------------
; Special values
; ------------------------------------------------------------

TIMER_NONE     = $FF

; ------------------------------------------------------------
; Timer range
;
; Expiry uses signed 16-bit tick difference:
;
;   expired if signed(system_ticks - target_tick) >= 0
;
; Therefore one sleep interval must be less than $8000 ticks.
;
; At 50 Hz:
;   $8000 ticks = about 10.9 minutes
; ------------------------------------------------------------

TIMER_MAX_DELTA = $7F

.endif
