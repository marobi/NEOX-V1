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

; ------------------------------------------------------------
; Syscall table location
; ------------------------------------------------------------

SYSCALL_BASE        = $C000
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

SYS_READ            = $03
SYS_WRITE           = $04
SYS_MONITOR         = $05

; ------------------------------------------------------------
; Fixed syscall entry addresses
; ------------------------------------------------------------

sys_read            = SYSCALL_BASE + (SYS_READ    * SYSCALL_ENTRY_SIZE)
sys_write           = SYSCALL_BASE + (SYS_WRITE   * SYSCALL_ENTRY_SIZE)
sys_monitor         = SYSCALL_BASE + (SYS_MONITOR * SYSCALL_ENTRY_SIZE)

; ------------------------------------------------------------
; Common errno values
; ------------------------------------------------------------

E_OK                = 0
EIO                 = 3
EINVAL              = 6
EBADF           	= 9
ENODEV          	= 10
ENOSYS          	= 11

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
