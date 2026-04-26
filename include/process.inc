; ============================================================
; process.inc
; NEOX - formal process descriptor definition
;
; Purpose:
;   Defines the logical per-process record layout and field
;   offsets. 
;
; ============================================================

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

; Optional future states
; PROC_BLOCKED  = $04
; PROC_ZOMBIE   = $05

PROC_FLAG_NONE     = $00
PROC_FLAG_MONITOR  = $01

.endif
