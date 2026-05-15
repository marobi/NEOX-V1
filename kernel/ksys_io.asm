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

.include "syscall.inc"
.include "fd.inc"
.include "process.inc"

.export ksys_read
.export ksys_console_read_blocking
.export ksys_write
.export ksys_close
.export ksys_dup
.export ksys_dup2

.import current_pid
.import proc_set_wait
.import sched_yield
.import rp_console_read_start
.import rp_console_read_finish

.import fd_read
.import fd_write
.import fd_close
.import fd_dup
.import fd_dup2

.importzp io_ptr
.importzp io_tmp

.segment "KERN_TEXT"

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
;   WAIT_CONSOLE blocking already happened in console_read
;   before this routine was entered.
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
; ksys_read
;
; Purpose:
;   Kernel-side syscall wrapper for read(fd, buf, len).
;
; Responsibility:
;   Decode syscall argument block only.
;
; Dispatch:
;   fd_read owns:
;     - fd validation
;     - fd permission checks
;     - open-object resolution
;     - device/file backend dispatch
; ------------------------------------------------------------

.proc ksys_read
    ; Save pointer to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Save fd temporarily on stack.
    ldy #rw_args::fd
    lda (io_ptr),y
    pha

    ; Save caller buffer pointer while io_ptr still points to rw_args.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Load requested transfer length.
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; FD/device layer expects io_ptr to point to the data buffer.
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte into A.
    pla

    ; Restore fd into Y.
    ply

    jsr fd_read
    rts
.endproc

; ------------------------------------------------------------
; ksys_write
;
; Purpose:
;   Kernel-side syscall wrapper for write(fd, buf, len).
;
; Responsibility:
;   Decode syscall argument block only.
;
; Dispatch:
;   fd_write owns:
;     - fd validation
;     - fd permission checks
;     - open-object resolution
;     - device/file backend dispatch
; ------------------------------------------------------------

.proc ksys_write
    ; Save pointer to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Save fd temporarily on stack.
    ldy #rw_args::fd
    lda (io_ptr),y
    pha

    ; Save caller buffer pointer while io_ptr still points to rw_args.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Load requested transfer length.
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; FD/device layer expects io_ptr to point to the data buffer.
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte into A.
    pla

    ; Restore fd into Y.
    ply

    jsr fd_write
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
