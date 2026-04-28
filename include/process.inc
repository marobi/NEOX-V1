.ifndef __PROCESS_INC__
__PROCESS_INC__ = 1

; ------------------------------------------------------------
; Process states
; ------------------------------------------------------------

PROC_EMPTY      = $00
PROC_NEW        = $01
PROC_READY      = $02
PROC_RUNNING    = $03
PROC_BLOCKED    = $04
PROC_ZOMBIE     = $05

; ------------------------------------------------------------
; Flags byte bit definitions
; ------------------------------------------------------------

PROC_FLAG_NONE          = $00
PROC_FLAG_IDLE          = $01
PROC_FLAG_ATTACHED_CON  = $02

.endif