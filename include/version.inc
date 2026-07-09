; ============================================================
; version.inc
; NEOX - kernel version constants
; ============================================================

.ifndef NEOX_VERSION_INC
NEOX_VERSION_INC = 1

NEOX_VERSION_MAJOR  = 0
NEOX_VERSION_MINOR  = 98
NEOX_VERSION_BUILD  = 85

.macro NEOX_VERSION_BYTES
    .byte "0.98.85"
.endmacro

.endif
