; ============================================================
; console_device.asm
; NEOX - console device operations
;
; Role:
;   Device backend for FD-based console I/O.
;
; Read policy:
;   - Only the PID selected by RP_CONSOLE_PID may consume input.
;   - console_owner_pid mirrors RP_CONSOLE_PID for kernel state/debug.
;   - If the current task does not own the console, read returns 0 bytes.
;   - If no character is ready, read returns 0 bytes.
;   - The actual RP mailbox read is only started when input is ready.
;
; Write policy:
;   - Console write is currently allowed for all tasks with a writable FD.
;   - FD permissions should be enforced above this layer.
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "syscall.inc"
.include "mailbox.inc"

.export console_ops
.export console_set_focus

.import current_pid
.import sched_lock
.import console_owner_pid
.import console_wait_pid

.import proc_set_blocked

.import rp_console_read
.import rp_console_write

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Device operation table
;
; Offsets must match DEVOP_* in fd.inc:
;   DEVOP_READ   = 0
;   DEVOP_WRITE  = 2
;   DEVOP_IOCTL  = 4
;   DEVOP_CLOSE  = 6
; ------------------------------------------------------------

console_ops:
    .word console_read
    .word console_write
    .word console_ioctl
    .word console_close


; ------------------------------------------------------------
; console_set_focus
;
; Input:
;   A = PID that owns keyboard focus
;       $FF = no console owner
;
; Effect:
;   Updates both the RP-visible focus byte and the kernel mirror used
;   by debug/status output.
;
; Notes:
;   This routine is not called by the scheduler. Console focus is a
;   user/supervisor policy decision, independent of which task currently
;   has CPU time.
; ------------------------------------------------------------

.proc console_set_focus
    sta RP_CONSOLE_PID
    sta console_owner_pid
    clc
    rts
.endproc

; ------------------------------------------------------------
; console_read
;
; Purpose:
;   Console device read for FD layer with dual-path handling:
;
;   1. Monitor / supervisor path (sched_lock != 0)
;      - Input is polled (nonblocking)
;      - No ownership checks
;      - Never blocks any process
;
;   2. Normal process path (sched_lock == 0)
;      - Only console_owner_pid may read
;      - If no data: process is BLOCKED and console_wait_pid is set
;
; Input:
;   A/X    = requested byte count
;   io_ptr = destination buffer
;
; Output:
;   C clear = success
;             A/X = bytes read (0 allowed)
;
;   C set   = special condition
;             Y = E_OK → process was blocked
;
; Invariants:
;   - Only one process may block on console (console_wait_pid)
;   - Monitor must not interfere with process blocking state
;   - RP_CONSOLE_RDY must be checked before calling rp_console_read
; ------------------------------------------------------------

.proc console_read
    ; Preserve requested length (A/X).
    pha
    phx

    ; --------------------------------------------------------
    ; Monitor / supervisor path
    ;
    ; When sched_lock != 0:
    ;   - We are in monitor or protected kernel context
    ;   - No process blocking is allowed
    ;   - Input is simply polled
    ; --------------------------------------------------------
    lda sched_lock
    bne @monitor_path

    ; --------------------------------------------------------
    ; Normal process path
    ;
    ; Only the accepted console owner may read input.
    ; --------------------------------------------------------
    lda console_owner_pid

    ; No owner assigned → no input allowed
    cmp #$FF
    beq @zero_read

    ; Not the owner → no input
    cmp current_pid
    bne @zero_read

    ; Owner requesting input → check readiness
    lda RP_CONSOLE_RDY
    bne @has_data

    ; --------------------------------------------------------
    ; Owner + no data → block process
    ; --------------------------------------------------------

    ; Record waiting PID
    lda current_pid
    sta console_wait_pid

    ; Block current process
    tax
    jsr proc_set_blocked

    ; Restore registers
    plx
    pla

    ; Signal "blocked, not error"
    ldy #E_OK
    sec
    rts

; ------------------------------------------------------------
; Monitor path: nonblocking polling only
; ------------------------------------------------------------
@monitor_path:
    lda RP_CONSOLE_RDY
    beq @zero_read

; ------------------------------------------------------------
; Data ready → perform actual read
; ------------------------------------------------------------
@has_data:
    plx
    pla
    jmp rp_console_read

; ------------------------------------------------------------
; Return 0 bytes (no data or not owner)
; ------------------------------------------------------------
@zero_read:
    plx
    pla
    lda #0
    tax
    clc
    rts
.endproc

; ------------------------------------------------------------
; console_write
;
; Input:
;   A/X = requested byte count
;   io_ptr = source buffer
;
; Output:
;   C clear = success
;             A/X = bytes written
;   C set   = failure
;             Y = errno
;
; Notes:
;   Write ownership is intentionally not enforced here yet. A process with
;   fd 1/2 attached to the console may write.
; ------------------------------------------------------------

.proc console_write
    jmp rp_console_write
.endproc

; ------------------------------------------------------------
; console_ioctl
;
; No console ioctl operations are implemented yet.
; ------------------------------------------------------------

.proc console_ioctl
    ldy #ENOSYS
    sec
    rts
.endproc

; ------------------------------------------------------------
; console_close
;
; Closing the console backend itself is a no-op. FD/open-object reference
; accounting belongs to the FD layer.
; ------------------------------------------------------------

.proc console_close
    clc
    rts
.endproc
