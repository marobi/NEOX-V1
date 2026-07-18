; ============================================================
; config.inc
; NEOX - kernel configuration
;
; Purpose:
; ============================================================

.ifndef __CONFIG_INC__
__CONFIG_INC__ = 1

; ------------------------------------------------------------
; Limits
; ------------------------------------------------------------

MAX_FDS     = 6          ; per-process descriptor count
OPEN_MAX    = 16         ; system-wide open object slots

; ------------------------------------------------------------
; Maximum simultaneously active processes
; ------------------------------------------------------------

MAX_PROCS   = 8

; ------------------------------------------------------------
; Maximum simultaneously active timer waits
; ------------------------------------------------------------

MAX_TIMER   = 8

;
;
;

MAX_PIPES       = 8
PIPE_BUF_SIZE   = 64

; ------------------------------------------------------------
; Filesystem path limits
; ------------------------------------------------------------

NEOX_CWD_MAX  = 32        ; process-private current-directory path bytes
NEOX_PATH_MAX = 64        ; kernel path resolver buffer bytes
; ============================================================
;
; ============================================================

USER_IMAGE_TABLE = $2000

; Final 32/32 virtual-memory split.
USER_SPACE_LIMIT = $8000
KERNEL_SHARED_BASE = $B020
KERNEL_OVERFLOW_BASE = $C000
MICMON_BASE = $D000
IO_PAGE_BASE = $E000
BIOS_BASE = $F000

; ------------------------------------------------------------
; Kernel
; ------------------------------------------------------------

KERNEL_BASE = $8000

; ------------------------------------------------------------
; Syscall table location
; ------------------------------------------------------------

SYSCALL_BASE = $F100

; ------------------------------------------------------------
; RP2350 mailbox control registers (MMIO)
;
; Layout:
;   Page E is shared I/O space
;   OS-owned mailbox doorbell starts at $E010
; ------------------------------------------------------------

RP_DOORBELL  = $E010

; ------------------------------------------------------------
; Shared RAM request/result block (ordinary shared RAM, not I/O)
;
; mailbox request block.
; ------------------------------------------------------------

RP_REQ_BASE  = $B000

.endif
