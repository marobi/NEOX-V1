; ============================================================
; pipe.inc
; NEOX - pipe constants
; ca65 / W65C02
; ============================================================

.ifndef NEOX_PIPE_INC
NEOX_PIPE_INC = 1

.include "config.inc"

PIPE_NONE       = $FF

PIPE_STATE_FREE        = $00
PIPE_STATE_READ_OPEN   = $01
PIPE_STATE_WRITE_OPEN  = $02
PIPE_STATE_USED        = PIPE_STATE_READ_OPEN | PIPE_STATE_WRITE_OPEN

PIPE_END_READ          = $01
PIPE_END_WRITE         = $02

.endif
