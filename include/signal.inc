; ============================================================
; signal.inc
; NEOX signal numbers
;
; Public signal numbers follow Linux:
;   SIG_INT  = 2
;   SIG_KILL = 9
;   SIG_CONT = 18
;   SIG_STOP = 19
; ============================================================

.ifndef __SIGNAL_INC__
__SIGNAL_INC__ = 1

SIG_NONE = 0
SIG_INT  = 2
SIG_KILL = 9
SIG_CONT = 18
SIG_STOP = 19

; Source compatibility for older NEOX assembly code.
SIG_HALT = SIG_STOP

.endif
