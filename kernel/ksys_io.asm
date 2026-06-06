; ============================================================
; ksys_io.asm
; NEOX - kernel-owned read/write syscall services
;
; Layering:
;   syscall_table.asm only jumps here through kernel.inc entries.
;   This file owns the real read/write implementation:
;
;       syscall ABI
;           -> fd_lookup
;           -> device resolver
;           -> device operation
;
; Calling convention from syscall stubs:
;   X/Y -> rw_args block
;
; Device operation convention:
;   io_ptr -> caller buffer
;   A/X    = requested length, low/high
;
; Return convention:
;   C clear = success
;             A/X = bytes transferred
;
;   C set   = failure
;             Y = errno
; ============================================================

.setcpu "65C02"

.include "debug.inc"
.include "syscall.inc"
.include "fd.inc"
.include "process.inc"
.include "lock.inc"

.export ksys_io_init
.export ksys_read
.export ksys_console_read_blocking
.export ksys_write
.export ksys_close
.export ksys_dup
.export ksys_dup2
.export ksys_pipe

.import current_pid
.import proc_set_wait
.import sched_yield
.import scheduler_wake_one

.import ksys_io_lock
.import ksys_io_owner
.import ksys_io_phase

.import rp_console_read_start
.import rp_console_read_finish
.import rp_console_write_finish

.import fd_read
.import fd_write
.import fd_close
.import fd_dup
.import fd_dup2
.import pipe_create

.importzp io_ptr

.segment "KERN_BSS"

; ------------------------------------------------------------
; ksys_io private scratch
;
; Protected by:
;   ksys_io_lock
;
; Rules:
;   - valid only while ksys_io_lock is owned
;   - not live across sched_yield unless this process owns
;     ksys_io_lock for the whole read/write operation
; ------------------------------------------------------------

ksys_rw_fd_tmp:
    .res 1

ksys_rw_len_lo:
    .res 1

ksys_rw_len_hi:
    .res 1

ksys_rw_buf_lo:
    .res 1

ksys_rw_buf_hi:
    .res 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_io_init
;
; Purpose:
;   Initialize ksys_io subsystem state.
;
; Notes:
;   ksys_io_lock is the real serialization lock for ksys_read
;   and ksys_write. It is not sched_lock.
; ------------------------------------------------------------

.proc ksys_io_init
    stz ksys_io_lock
    rts
.endproc

; ------------------------------------------------------------
; ksys_console_read_blocking
;
; Purpose:
;   Submit a console read request and wait for RP completion.
;
; Scheduling:
;   Current implementation polls until RP completion.
;   Later this should become a cooperative wait/yield path.
;
; Important:
;   This routine may run while ksys_io_lock is owned by the
;   calling read/write syscall path.
; ------------------------------------------------------------

.proc ksys_console_read_blocking
    jsr rp_console_read_start
    bcs @fail

@wait:
    jsr rp_console_read_finish
    bcc @done

    cpy #E_OK
    bne @fail

    bra @wait

@done:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_console_write_wait
;
; Wait for an async RP console write to complete.
;
; Important:
;   This may be reached while ksys_io_lock is owned by the
;   calling read/write syscall path.
;   sched_lock is not held here.
;   rp_lock is held by the in-flight RP transaction.
; ------------------------------------------------------------

.proc ksys_console_write_wait
@wait:
    jsr rp_console_write_finish
    bcc @done

    cpy #E_OK
    bne @fail

    ; Optional later:
    ;   jsr sched_yield
    ;
    ; For now this is a polling wait. It may run while the
    ; caller owns ksys_io_lock. It does not hold sched_lock.
    bra @wait

@done:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_console_read_wait
;
; Wait for an async RP console read to complete.
;
; Important:
;   This may be reached while ksys_io_lock is owned by the
;   calling read/write syscall path.
;   sched_lock is not held here.
;   rp_lock is held by the in-flight RP transaction.
; ------------------------------------------------------------

.proc ksys_console_read_wait
@wait:
    jsr rp_console_read_finish
    bcc @done

    cpy #E_OK
    bne @fail

    bra @wait

@done:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_io_acquire
;
; Purpose:
;   Acquire global read/write syscall serialization.
;
; Behavior:
;   If ksys_io_lock is free:
;       acquire it
;       set ksys_io_owner = current_pid
;       return
;
;   If busy and owned by another process:
;       block current process on WAIT_KSYS_IO object 0
;       sched_yield
;       retry when woken
;
;   If busy and already owned by current_pid:
;       trap. Recursive KIO acquisition is a kernel bug.
;
; Lost-wake protection:
;   IRQs are disabled across failed try-acquire and proc_set_wait.
;   This prevents the lock owner from releasing+waking between
;   failed acquire and wait registration.
;
; Return:
;   C set = acquired
; ------------------------------------------------------------

.proc ksys_io_acquire
@retry:
    php
    sei

    LOCK_TRY_ACQUIRE ksys_io_lock
    bcs @acquired

    ; DEBUG-BEGIN: detect recursive ksys_io_lock acquire
    lda ksys_io_owner
    cmp current_pid
    bne @wait_for_owner

    lda #DBG_MARK_KIO_RECURSE
    sta sched_debug_marker
    lda current_pid
    sta sched_debug_pid

@trap_recursive:
    bra @trap_recursive
    ; DEBUG-END: detect recursive ksys_io_lock acquire

@wait_for_owner:
    ldx current_pid
    lda #WAIT_KSYS_IO
    ldy #$00
    jsr proc_set_wait

    plp

    jsr sched_yield
    bra @retry

@acquired:
    ; DEBUG-BEGIN: ksys_io_lock owner set
    ldx current_pid
    stx ksys_io_owner
    ; DEBUG-END: ksys_io_lock owner set

    plp
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_io_release
;
; Purpose:
;   Release global read/write syscall serialization and wake one
;   process waiting on WAIT_KSYS_IO object 0.
;
; Policy:
;   Wake one waiter only. ksys_io_lock is a single-owner
;   serialization resource.
;
; Notes:
;   Release+wake is protected with IRQs disabled so no 6502-side
;   scheduler path can interleave between lock release and wake.
;
; Return:
;   C set
; ------------------------------------------------------------

.proc ksys_io_release
    php
    sei

    ; Release the lock before clearing debug owner metadata.
    ; External RP-side ps can read shared state asynchronously; this
    ; ordering avoids the misleading stable-looking combination:
    ;   ksys_io_lock = 1, ksys_io_owner = DBG_OWNER_NONE.
    LOCK_RELEASE ksys_io_lock

    ; DEBUG-BEGIN: ksys_io_lock owner clear
    lda #DBG_OWNER_NONE
    sta ksys_io_owner

    lda #DBG_KIO_IDLE
    sta ksys_io_phase
    ; DEBUG-END: ksys_io_lock owner clear

    lda #WAIT_KSYS_IO
    ldy #$00
    jsr scheduler_wake_one

    plp
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_read
;
; Purpose:
;   Kernel-side syscall wrapper for read(fd, buf, len).
;
; Input:
;   X/Y -> rw_args block
;
; Return:
;   C clear = success
;       A/X = bytes read
;
;   C set = failure
;       Y = errno
;
; Serialization:
;   Globally serialized with ksys_write by ksys_io_lock.
; ------------------------------------------------------------

.proc ksys_read
    ; Preserve syscall argument pointer across possible
    ; WAIT_KSYS_IO + sched_yield in ksys_io_acquire.
    phx
    phy

    jsr ksys_io_acquire

    ply
    plx

    ; io_ptr temporarily points to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Decode fd.
    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_tmp

    ; Decode caller buffer pointer.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi

    ; Decode requested length.
    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi

    ; FD/backend layer expects io_ptr to point to caller buffer.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr fd_read

    ; Preserve fd_read result across release/wake.
    php
    pha
    phx
    phy

    jsr ksys_io_release

    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; ksys_write
;
; Purpose:
;   Kernel-side syscall wrapper for write(fd, buf, len).
;
; Input:
;   X/Y -> rw_args block
;
; Return:
;   C clear = success
;       A/X = bytes written
;
;   C set = failure
;       Y = errno
;
; Serialization:
;   Globally serialized with ksys_read by ksys_io_lock.
; ------------------------------------------------------------

.proc ksys_write
    ; Preserve syscall argument pointer across possible
    ; WAIT_KSYS_IO + sched_yield in ksys_io_acquire.
    phx
    phy

    jsr ksys_io_acquire

    ply
    plx

    ; io_ptr temporarily points to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Decode fd.
    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_tmp

    ; Decode caller buffer pointer.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi

    ; Decode requested length.
    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi

    ; FD/backend layer expects io_ptr to point to caller buffer.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr fd_write

    ; Preserve fd_write result across release/wake.
    php
    pha
    phx
    phy

    jsr ksys_io_release

    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; ksys_close
;
; Purpose:
;   Kernel-side syscall wrapper for close(fd).
;
; Input:
;   A = fd number
;
; Output:
;   C clear = success
;   A = 0
;   X = 0
;
;   C set   = failure
;   Y = errno
;
; Responsibility:
;   Decode syscall argument only.
;
; Dispatch:
;   fd_close owns:
;     - fd validation
;     - process fd table cleanup
;     - open-object refcount update
;     - backend close dispatch
; ------------------------------------------------------------

.proc ksys_close
    jsr fd_close
    rts
.endproc

; ------------------------------------------------------------
; ksys_dup
;
; Input:
;   A = old fd
;
; Output:
;   C clear = success
;             A = new fd
;             X = 0
;
;   C set   = failure
;             Y = errno
; ------------------------------------------------------------

.proc ksys_dup
    jmp fd_dup
.endproc

; ------------------------------------------------------------
; ksys_dup2
;
; Input:
;   A = old fd
;   Y = new fd
;
; Output:
;   C clear = success
;             A = new fd
;             X = 0
;
;   C set   = failure
;             Y = errno
; ------------------------------------------------------------

.proc ksys_dup2
    jmp fd_dup2
.endproc

; ------------------------------------------------------------
; ksys_pipe
;
; Purpose:
;   Create anonymous pipe for current process.
;
; Return:
;   C clear = success
;             A = read fd
;             X = write fd
;
;   C set   = failure
;             Y = errno
; ------------------------------------------------------------

.proc ksys_pipe
    jmp pipe_create
.endproc
