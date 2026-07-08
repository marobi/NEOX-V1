; ============================================================
; fd.inc
; NEOX - file descriptor and open object definitions
;
; Purpose:
;   devices/files. 
;   This forms the FD/open-object/device layer
;   used by read/write/close/dup/dup2.;
; Model:
;   process fd table → open object table → device/file backend
; ============================================================

.ifndef __FD_INC__
__FD_INC__ = 1

.include "config.inc"

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
OBJ_FILE    = $02        ; RP filesystem file handle
OBJ_PIPE    = $03        ; reserved
OBJ_DIR     = $04        ; RP filesystem directory handle


; ------------------------------------------------------------
; FD clone argument block
;
; Used by kernel-internal cross-process descriptor cloning.
; The source descriptor is resolved in source_pid/source_fd and
; attached to target_pid/target_fd with the same per-FD flags.
; ------------------------------------------------------------

.struct fd_clone_args
    source_pid      .byte
    source_fd       .byte
    target_pid      .byte
    target_fd       .byte
.endstruct

FD_CLONE_ARGS_SIZE = .sizeof(fd_clone_args)

; ------------------------------------------------------------
; Device identifiers
; ------------------------------------------------------------

DEV_NONE        = $00
DEV_CONSOLE     = $01

DEV_MAX         = $02

; ------------------------------------------------------------
; Device operation offsets
; ------------------------------------------------------------

DEVOP_READ      = 0
DEVOP_WRITE     = 2
DEVOP_IOCTL     = 4
DEVOP_CLOSE     = 6

.endif
