; ============================================================
; syscall.inc
; NEOX - syscall definitions
;
; Purpose:
;   Defines syscall numbers, fixed syscall entry addresses,
;   error codes, and common syscall argument structures.
;
; Architecture:
;   - Syscall jump table is located in shared page C
;   - Each syscall entry is a 3-byte JMP stub
;   - User code calls fixed syscall entry addresses
;
; Notes:
;   SYS_MONITOR enters supervisor/MICMON context through the
;   kernel-defined monitor entry path. It is a controlled
;   privileged transfer, not direct user control of MMU/scheduler.
; ============================================================

.ifndef __SYSCALL_INC__
__SYSCALL_INC__ = 1

.include "config.inc"

SYSCALL_ENTRY_SIZE  = 3

; ------------------------------------------------------------
; Standard file descriptors
; ------------------------------------------------------------

STDIN               = 0
STDOUT              = 1
STDERR              = 2

; ------------------------------------------------------------
; Syscall numbers
; ------------------------------------------------------------
SYS_EXIT			= $00
SYS_CLOSE			= $02
SYS_READ            = $03
SYS_WRITE           = $04
SYS_MONITOR         = $05
SYS_PIPE			= $0A
SYS_YIELD           = $0B
SYS_SLEEP           = $0E
SYS_DUP				= $0F
SYS_DUP2			= $10

; ------------------------------------------------------------
; Fixed syscall entry addresses
; ------------------------------------------------------------

sys_exit            = SYSCALL_BASE + (SYS_EXIT    * SYSCALL_ENTRY_SIZE)
sys_close           = SYSCALL_BASE + (SYS_CLOSE   * SYSCALL_ENTRY_SIZE)
sys_read            = SYSCALL_BASE + (SYS_READ    * SYSCALL_ENTRY_SIZE)
sys_write           = SYSCALL_BASE + (SYS_WRITE   * SYSCALL_ENTRY_SIZE)
sys_monitor         = SYSCALL_BASE + (SYS_MONITOR * SYSCALL_ENTRY_SIZE)
sys_pipe            = SYSCALL_BASE + (SYS_PIPE    * SYSCALL_ENTRY_SIZE)
sys_yield           = SYSCALL_BASE + (SYS_YIELD   * SYSCALL_ENTRY_SIZE)
sys_sleep           = SYSCALL_BASE + (SYS_SLEEP   * SYSCALL_ENTRY_SIZE)
sys_dup				= SYSCALL_BASE + (SYS_DUP     * SYSCALL_ENTRY_SIZE)
sys_dup2			= SYSCALL_BASE + (SYS_DUP2    * SYSCALL_ENTRY_SIZE)

; ------------------------------------------------------------
; Common errno values
; ------------------------------------------------------------

E_OK                = 0
EIO                 = 3
EINVAL              = 6
EMFILE              = 8        ; too many open file descriptors
EBADF               = 9
ENODEV              = 10
ENOSYS              = 11
EAGAIN              = 12       ; operation would block / try again
ENOMEM              = 13       ; no free kernel memory/object/table slot
EPIPE               = 14       ; write on pipe with no readers

; ------------------------------------------------------------
; Common read/write argument block
;
; fd:
;   STDIN / STDOUT / STDERR
;
; buf_ptr:
;   Pointer to caller buffer in the current task context
;
; len:
;   Requested transfer length
; ------------------------------------------------------------

.struct rw_args
    fd              .byte
    reserved        .byte
    buf_ptr         .word
    len             .word
.endstruct

RW_ARGS_SIZE = .sizeof(rw_args)

; ------------------------------------------------------------
; SYSCALL helper macro
;
; Purpose:
;   Load X/Y with the address of an argument block and call the
;   fixed syscall entry.
;
; Example:
;   SYSCALL my_args, sys_write
; ------------------------------------------------------------

.macro SYSCALL argblk, entry
    ldx #<argblk
    ldy #>argblk
    jsr entry
.endmacro

.endif
