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

.include "lock.inc"
.include "syscall.inc"
.include "fd.inc"
.include "process.inc"

.export ksys_io_init
.export ksys_read
.export ksys_console_read_blocking
.export ksys_write
.export ksys_close
.export ksys_dup
.export ksys_dup2
.export ksys_pipe

.import sched_lock_enter
.import sched_lock_leave

.import ksys_io_lock

.import current_pid

.import fd_resolve_read
.import fd_resolve_write

.import pipe_read
.import pipe_write
.import rp_console_read_start
.import rp_console_read_finish
.import rp_console_write_start
.import rp_console_write_finish

.import fd_close
.import fd_dup
.import fd_dup2
.import pipe_create

.importzp io_ptr

.importzp pipe_ptr

.segment "KERN_BSS"

; ------------------------------------------------------------
; ksys_io private scratch
;
; Protected by:
;   ksys_io_lock
;
; Rules:
;   - valid only while ksys_io_lock is held
;   - never live across sched_yield
;   - never live across WAIT_* blocking
;   - never live across an indefinite RP wait
;
; io_ptr remains in zero page because fd/device/backend code
; needs a zero-page pointer for indirect indexed addressing.
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
;   While the RP request is in flight, the current task yields
;   cooperatively so other runnable tasks may execute.
;
; Important:
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
;   ksys_io_lock is not held here.
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
    ; For now this is a polling wait, but it no longer holds
    ; ksys_io_lock or the scheduler gate.
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
;   ksys_io_lock is not held here.
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
; ksys_read
;
; Generic read syscall dispatch.
;
; Supports:
;   OBJ_PIPE
;   OBJ_DEVICE / DEV_CONSOLE
;
; Locking model:
;   ksys_io_lock protects syscall scratch and io_ptr while live.
;
;   Pipe backend:
;       executed while ksys_io_lock is held because pipe backend
;       is nonblocking and uses pipe_ptr/io-derived state.
;
;   Console backend:
;       RP request is started while ksys_io_lock is held, because
;       io_ptr must be stable while copied into the RP request.
;       ksys_io_lock is then released before waiting for RP_DONE.
; ------------------------------------------------------------

.proc ksys_read
    phx
    phy

    jsr sched_lock_enter
    LOCK_ACQUIRE ksys_io_lock

    ply
    plx

    ; Decode rw_args while serialized.
    stx io_ptr
    sty io_ptr+1

    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_tmp

    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi

    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi

    ; Resolve FD for read.
    ldy ksys_rw_fd_tmp
    jsr fd_resolve_read
    bcs @locked_fail

    cmp #OBJ_PIPE
    beq @pipe

    cmp #OBJ_DEVICE
    beq @device

    ldy #ENODEV
    bra @locked_fail_y

@pipe:
    ; X = open object.
    ;
    ; pipe_read uses pipe_ptr as the user buffer pointer.
    lda ksys_rw_buf_lo
    sta pipe_ptr
    lda ksys_rw_buf_hi
    sta pipe_ptr+1

;    tay                         ; wrong if left from type; reload obj below
    ; restore open object from X into Y
    txa
    tay

    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr pipe_read

    php
    pha
    phx
    phy

    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave

    ply
    plx
    pla
    plp
    rts

@device:
    ; Only console device exists for now.
    cpy #DEV_CONSOLE
    beq @console

    ldy #ENODEV
    bra @locked_fail_y

@console:
    ; Start RP console read while io_ptr is stable.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr rp_console_read_start
    bcs @locked_fail

    ; The RP request now owns copied pointer/length in the
    ; mailbox request block. io_ptr no longer needs protection.
    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave

    jmp ksys_console_read_wait

@locked_fail:
    ; Preserve errno already in Y.
@locked_fail_y:
    phy
    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave
    ply
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_write
;
; Generic write syscall dispatch.
;
; Supports:
;   OBJ_PIPE
;   OBJ_DEVICE / DEV_CONSOLE
;
; Locking model:
;   ksys_io_lock protects syscall scratch and io_ptr while live.
;
;   Pipe backend:
;       executed while ksys_io_lock is held because pipe backend
;       is nonblocking.
;
;   Console backend:
;       RP request is started while ksys_io_lock is held, then
;       ksys_io_lock is released before waiting for RP_DONE.
; ------------------------------------------------------------

.proc ksys_write
    phx
    phy

    jsr sched_lock_enter
    LOCK_ACQUIRE ksys_io_lock

    ply
    plx

    ; Decode rw_args while serialized.
    stx io_ptr
    sty io_ptr+1

    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_tmp

    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi

    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi

    ; Resolve FD for write.
    ldy ksys_rw_fd_tmp
    jsr fd_resolve_write
    bcs @locked_fail

    cmp #OBJ_PIPE
    beq @pipe

    cmp #OBJ_DEVICE
    beq @device

    ldy #ENODEV
    bra @locked_fail_y

@pipe:
    lda ksys_rw_buf_lo
    sta pipe_ptr
    lda ksys_rw_buf_hi
    sta pipe_ptr+1

    txa
    tay                         ; Y = open object

    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr pipe_write

    php
    pha
    phx
    phy

    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave

    ply
    plx
    pla
    plp
    rts

@device:
    ; Only console device exists for now.
    cpy #DEV_CONSOLE
    beq @console

    ldy #ENODEV
    bra @locked_fail_y

@console:
    ; Start RP console write while io_ptr is stable.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi

    jsr rp_console_write_start
    bcs @locked_fail

    ; The RP request now owns copied pointer/length in the
    ; mailbox request block. io_ptr no longer needs protection.
    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave

    jmp ksys_console_write_wait

@locked_fail:
    ; Preserve errno already in Y.
@locked_fail_y:
    phy
    LOCK_RELEASE ksys_io_lock
    jsr sched_lock_leave
    ply
    sec
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
