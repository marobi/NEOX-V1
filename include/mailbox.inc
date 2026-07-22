; ============================================================
; mailbox.inc
; NEOX - RP2350 mailbox / request block definitions
;
; Purpose:
;   Defines the shared ABI v2 request/result block layout used
;   for communication between the 6502 kernel/syscall code and
;   the RP2350 co-processor.
;
; Architecture:
;   - Logical pages 0..7 are private per context
;   - Logical pages 8..F are shared across all contexts; page E is I/O
;   - MMIO control registers live in shared I/O page
;
; ABI v2:
;   - RP_REQ_BASE is $B000 in ordinary shared RAM
;   - Request block starts with RP_GROUP and RP_CMD
;   - RP_DOORBELL is trigger-only; command identity is not
;     encoded in the doorbell value anymore.
; ============================================================

.ifndef __MAILBOX_INC__
__MAILBOX_INC__ = 1

.include "config.inc"

; ------------------------------------------------------------
; Request / result block layout, ABI v2
; ------------------------------------------------------------

RP_GROUP            = RP_REQ_BASE + 0
RP_CMD              = RP_REQ_BASE + 1
RP_STATUS           = RP_REQ_BASE + 2
RP_ERR              = RP_REQ_BASE + 3

RP_FLAGS            = RP_REQ_BASE + 4
RP_STATE            = RP_REQ_BASE + 5

RP_ARG0L            = RP_REQ_BASE + 6
RP_ARG0H            = RP_REQ_BASE + 7
RP_ARG1L            = RP_REQ_BASE + 8
RP_ARG1H            = RP_REQ_BASE + 9
RP_ARG2L            = RP_REQ_BASE + 10
RP_ARG2H            = RP_REQ_BASE + 11

RP_RES0L            = RP_REQ_BASE + 12
RP_RES0H            = RP_REQ_BASE + 13
RP_RES1L            = RP_REQ_BASE + 14
RP_RES1H            = RP_REQ_BASE + 15

; ------------------------------------------------------------
; Other shared RP state bytes
; ------------------------------------------------------------

RP_IRQ_SOURCE       = RP_REQ_BASE + 16
RP_CONSOLE_PID      = RP_REQ_BASE + 17
RP_CONSOLE_RDY      = RP_REQ_BASE + 18
RP_IRQ_STATE        = RP_REQ_BASE + 19

; ------------------------------------------------------------
; RP_STATUS values
; ------------------------------------------------------------

RP_IDLE             = $00
RP_BUSY             = $01
RP_DONE             = $02
RP_ERROR            = $03

; ------------------------------------------------------------
; RP_GROUP values
; ------------------------------------------------------------

RP_GROUP_NONE       = $00
RP_GROUP_CONSOLE    = $01
RP_GROUP_FS         = $02
RP_GROUP_SYSTEM     = $03

; ------------------------------------------------------------
; RP_CMD values inside RP_GROUP_CONSOLE
; ------------------------------------------------------------

RP_CON_CMD_NONE     = $00
RP_CON_CMD_WRITE    = $01
RP_CON_CMD_READ     = $02

; ------------------------------------------------------------
; RP_CMD values inside RP_GROUP_FS
; ------------------------------------------------------------

RP_FS_CMD_NONE      = $00
RP_FS_CMD_EXEC      = $11

; Generic filesystem operations carried in RP_STATE. Values $01-$10 retain
; their established numeric assignments, but are no longer accepted as direct
; RP_CMD values.
RP_FS_OP_STATUS        = $01
RP_FS_OP_OPEN          = $02
RP_FS_OP_READ          = $03
RP_FS_OP_CLOSE         = $04
RP_FS_OP_WRITE         = $05
RP_FS_OP_LOAD          = $06
RP_FS_OP_SAVE          = $07
RP_FS_OP_SEEK          = $08
RP_FS_OP_TELL          = $09
RP_FS_OP_DELETE        = $0A
RP_FS_OP_RENAME        = $0B
RP_FS_OP_OPENDIR       = $0C
RP_FS_OP_READDIR       = $0D
RP_FS_OP_CLOSEDIR      = $0E
RP_FS_OP_MKDIR         = $0F
RP_FS_OP_RMDIR         = $10
RP_FS_OP_CWD_INIT_ROOT = $12
RP_FS_OP_CWD_CLONE     = $13
RP_FS_OP_CHDIR         = $14
RP_FS_OP_GETCWD        = $15

RP_FS_SEEK_SET      = $00
RP_FS_SEEK_CUR      = $01
RP_FS_SEEK_END      = $02

; ------------------------------------------------------------
; RP_DOORBELL trigger value for ABI v2
; ------------------------------------------------------------

RP_DOORBELL_TRIGGER = $01

; ------------------------------------------------------------
; RP_FLAGS values
; ------------------------------------------------------------

RP_FLAG_NONE        = $00

; ------------------------------------------------------------
; RP_IRQ_SOURCE values
; ------------------------------------------------------------

RP_IRQ_SRC_NONE     = $00
RP_IRQ_SRC_TIMER    = $01
RP_IRQ_SRC_MONITOR  = $02
RP_IRQ_SRC_FS_DONE  = $03
RP_IRQ_SRC_CONSOLE_BREAK = $04

.endif
