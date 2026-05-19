; ============================================================
; pipe.inc
; NEOX - pipe constants
; ca65 / W65C02
; ============================================================

.ifndef NEOX_PIPE_INC
NEOX_PIPE_INC = 1

.include "config.inc"

PIPE_NONE       = $FF

PIPE_FREE       = $00
PIPE_USED       = $01

PIPE_END_READ   = $01
PIPE_END_WRITE  = $02

.endif
