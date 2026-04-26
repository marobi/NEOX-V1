; ============================================================
; mailbox.inc
; NEOX - RP2350 mailbox / request block definitions
;
; Purpose:
;   Defines the shared request/result block layout used for
;   communication between the 6502 kernel/syscall code and the
;   RP2350 co-processor.
;
; Architecture:
;   - Logical pages 0..7 are private per context
;   - Logical pages 8..F are shared across all contexts
;   - Therefore the request/result block must NOT live in low
;     RAM such as $02C0, because that would be private
;   - MMIO control registers live in shared I/O page D
;
; Design:
;   - RP_REQ_BASE points at a shared RAM block
;   - RP_DOORBELL / RP_STATUS are MMIO registers in page D
;   - The mailbox is a global system resource
;
; Notes:
;   All code using these definitions must treat the request
;   block as shared writable system state.
; ============================================================

.ifndef __MAILBOX_INC__
__MAILBOX_INC__ = 1

; ------------------------------------------------------------
; RP2350 mailbox control registers (MMIO)
;
; Layout:
;   Page D is shared I/O space
;   $D000-$D004 are already used by BIOS
;   OS-owned mailbox control starts at $D010
; ------------------------------------------------------------

RP_DOORBELL         = $D010

; ------------------------------------------------------------
; Shared RAM request/result block
;
; Why here:
;   $80C0 is in shared page 8, so all contexts see the same
;   mailbox request block.
; ------------------------------------------------------------

RP_REQ_BASE         = $80C0

; ------------------------------------------------------------
; Request / result block layout
;
; Request fields written by the 6502:
;   RP_ARG0L/H
;   RP_ARG1L/H
;   RP_ARG2L/H
;
; Result / status fields written by RP2350:
;   RP_RES0L/H
;   RP_ERR
;   RP_FLAGS
;   RP_STATE
; ------------------------------------------------------------

RP_ARG0L            = RP_REQ_BASE + 0
RP_ARG0H            = RP_REQ_BASE + 1
RP_ARG1L            = RP_REQ_BASE + 2
RP_ARG1H            = RP_REQ_BASE + 3
RP_ARG2L            = RP_REQ_BASE + 4
RP_ARG2H            = RP_REQ_BASE + 5

RP_RES0L            = RP_REQ_BASE + 6
RP_RES0H            = RP_REQ_BASE + 7
RP_ERR              = RP_REQ_BASE + 8
RP_FLAGS            = RP_REQ_BASE + 9
RP_STATE            = RP_REQ_BASE + 10

; ------------------------------------------------------------

RP_STATUS           = RP_REQ_BASE + 11
RP_IRQ_SOURCE       = RP_REQ_BASE + 12
RP_CONSOLE_PID      = RP_REQ_BASE + 13
RP_CONSOLE_RDY      = RP_REQ_BASE + 14

; ------------------------------------------------------------
; RP_STATUS values
; ------------------------------------------------------------

RP_IDLE             = $00
RP_BUSY             = $01
RP_DONE             = $02
RP_ERROR            = $03

; ------------------------------------------------------------
; RP_CMD values
;
; Console:
;   RP_CMD_CON_WRITE
;   RP_CMD_CON_READ
;
; Block I/O:
;   RP_CMD_BLK_READ
;   RP_CMD_BLK_WRITE
; ------------------------------------------------------------

RP_CMD_NONE         = $00

RP_CMD_CON_WRITE    = $10
RP_CMD_CON_READ     = $11

; ------------------------------------------------------------
; RP_FLAGS values
;
; Currently no flags are defined beyond "none".
; ------------------------------------------------------------

RP_FLAG_NONE        = $00

; ------------------------------------------------------------
; RP_IRQ_SOURCE values
; ------------------------------------------------------------
RP_IRQ_SRC_NONE    = $00
RP_IRQ_SRC_TIMER   = $01
RP_IRQ_SRC_MONITOR = $02

.endif
