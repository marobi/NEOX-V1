; ============================================================
; console_device.asm
; NEOX - console device operations
;
; Role:
;   Device backend for FD-based console I/O.
;
; Read policy:
;   - console_read uses console_owner_pid only
;   - a normal non-owner returns EAGAIN to the syscall layer and blocks
;     in WAIT_CONSOLE
;   - a normal owner with no data also blocks in WAIT_CONSOLE
;   - monitor/supervisor path polls and never blocks
;   - the actual RP mailbox read is only started when input is ready
;
; Write policy:
;   - Console write is currently allowed for all tasks with a writable FD.
;   - FD permissions should be enforced above this layer.
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "signal.inc"
.include "syscall.inc"
.include "mailbox.inc"
.include "scheduler_defs.inc"

.export console_ops

.export console_monitor_enter
.export console_monitor_exit

.import active_pid
.import sched_lock
.import console_owner_pid
.import proc_flags
.import proc_signal_pending

.import monitor_active

.import rp_console_read
.import rp_console_write

.import console_read_len_lo
.import console_read_len_hi

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
;
; ------------------------------------------------------------
.proc console_monitor_enter
    lda #$01
    sta monitor_active

    ; discard task-visible pending input
    stz RP_CONSOLE_RDY

    clc
    rts
.endproc

; ------------------------------------------------------------
;
; ------------------------------------------------------------
.proc console_monitor_exit
    ; discard monitor extra keys / stale ready state
    stz RP_CONSOLE_RDY

    stz monitor_active

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
;   2. Console blocking uses the generic wait_reason/wait_object model
;
; Input:
;   A/X    = requested byte count
;   io_ptr = destination buffer
;
; Output:
;   C clear = success
;             A/X = bytes read (0 allowed)
; Invariants:
;   - Only one process may block on console
;   - Monitor must not interfere with process blocking state
;   - RP_CONSOLE_RDY must be checked before calling rp_console_read
; ------------------------------------------------------------

.proc console_read
    ; Save requested length once for this read call.
    ;
    ; The routine may block and resume through sched_yield.
    ; After that resume, A/X are not reliable anymore.
    sta console_read_len_lo
    stx console_read_len_hi

@retry:
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

    ; A process configured for interruptible SIG_INT handling consumes the
    ; pending signal at its console-read boundary. This cancels the current
    ; line without terminating the process.
    ldx active_pid
    lda proc_flags,x
    and #PROC_FLAG_SIGINT_INTERRUPT
    beq @normal_process

    lda proc_signal_pending,x
    cmp #SIG_INT
    bne @normal_process

    stz proc_signal_pending,x
    ldy #EINTR
    sec
    rts

@normal_process:
    ; --------------------------------------------------------
    ; Normal process path
    ;
    ; Only the accepted console owner may read input. If no
    ; owner exists yet, the first normal reader becomes owner.
    ; --------------------------------------------------------
    lda console_owner_pid

    cmp #$FF
    bne @owner_known

    lda active_pid
    cmp #IDLE_PID
    beq @zero_read

    sta console_owner_pid
    bra @owner_ok

@owner_known:
    cmp active_pid
    beq @owner_ok

    ; A normal process that does not own the console must sleep rather than
    ; observe a false EOF/empty read. ksys_read translates EAGAIN for a console
    ; descriptor into WAIT_CONSOLE, releases FILE_IO, yields, and retries after
    ; the process is woken.
    ldy #EAGAIN
    sec
    rts

@owner_ok:
    lda RP_CONSOLE_RDY
    bne @has_data

    ; Normal owner but no data.
    ; Backend must not block internally.
    ldy #EAGAIN
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
    lda console_read_len_lo
    ldx console_read_len_hi
    jmp rp_console_read
	
; ------------------------------------------------------------
; Return 0 bytes for monitor/supervisor polling with no data.
; Normal processes never use this as a no-owner result.
; ------------------------------------------------------------
@zero_read:
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
