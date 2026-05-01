; ============================================================
; fd.inc
; NEOX - file descriptor and open object definitions
;
; Purpose:
;   Defines the abstraction layer between processes and
;   devices/files. This is the first step toward a UNIX-like
;   I/O model.
;
; Model:
;   process fd table → open object table → device/file backend
; ============================================================

.ifndef __FD_INC__
__FD_INC__ = 1

; ------------------------------------------------------------
; Limits
; ------------------------------------------------------------

MAX_FDS     = 4          ; per-process descriptor count
OPEN_MAX    = 8          ; system-wide open object slots

; ------------------------------------------------------------
; FD values
; ------------------------------------------------------------
FD_NONE     = $FF        ; invalid / unused descriptor

; ------------------------------------------------------------
; FD flags (per process)
;
; These describe how the process uses the descriptor.
; ------------------------------------------------------------

FD_FLAG_READ    = $01
FD_FLAG_WRITE   = $02
FD_FLAG_CLOEXEC = $80    ; reserved for later exec() support

; ------------------------------------------------------------
; Open object types (system-wide)
;
; Each open object represents a shared resource. Multiple
; processes may reference the same object.
; ------------------------------------------------------------

OBJ_NONE    = $00
OBJ_DEVICE  = $01        ; console for now
OBJ_FILE    = $02        ; reserved
OBJ_PIPE    = $03        ; reserved

; ------------------------------------------------------------
; Device identifiers
; ------------------------------------------------------------

DEV_NONE        = $00
DEV_CONSOLE     = $01

.endif
