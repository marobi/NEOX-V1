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

.export ksys_read
.export ksys_write

.import fd_lookup
.import dev_resolve_op
.import dev_call

.importzp io_ptr
.importzp io_tmp

.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_read
;
; Purpose:
;   Kernel-side implementation of read(fd, buf, len).
;
; Flow:
;   1. Decode fd from rw_args.
;   2. Resolve fd -> open object.
;   3. Resolve open object -> device read operation.
;   4. Decode buf/len.
;   5. Call the resolved device read operation.
;
; Important:
;   fd_lookup returns the open object index in X.
;   dev_resolve_op must preserve X so the device op can inspect
;   open-object state if needed.
; ------------------------------------------------------------

.proc ksys_read
    ; Save pointer to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Resolve fd to open object.
    ldy #rw_args::fd
    lda (io_ptr),y
    jsr fd_lookup
    bcc @fd_ok
    rts

@fd_ok:
    ; Resolve the device READ operation for this open object.
    lda #DEVOP_READ
    jsr dev_resolve_op
    bcc @op_ok
    rts

@op_ok:
    ; Save caller buffer pointer while io_ptr still points to rw_args.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Load requested transfer length.
    ; Low byte is temporarily pushed while high byte goes into X.
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; Device/RP console layer expects io_ptr to point to the data buffer.
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte into A.
    pla

    ; Call resolved device read routine.
    jsr dev_call
    rts
.endproc

; ------------------------------------------------------------
; ksys_write
;
; Purpose:
;   Kernel-side implementation of write(fd, buf, len).
;
; Flow:
;   Same as ksys_read, but resolves DEVOP_WRITE.
;
; Notes:
;   Permission checks should eventually use proc_fd_flags.
;   For now fd_lookup validates descriptor existence and the
;   device layer dispatches based on the open object.
; ------------------------------------------------------------

.proc ksys_write
    ; Save pointer to rw_args.
    stx io_ptr
    sty io_ptr+1

    ; Resolve fd to open object.
    ldy #rw_args::fd
    lda (io_ptr),y
    jsr fd_lookup
    bcc @fd_ok
    rts

@fd_ok:
    ; Resolve the device WRITE operation for this open object.
    lda #DEVOP_WRITE
    jsr dev_resolve_op
    bcc @op_ok
    rts

@op_ok:
    ; Save caller buffer pointer while io_ptr still points to rw_args.
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Load requested transfer length.
    ; Low byte is temporarily pushed while high byte goes into X.
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; Device/RP console layer expects io_ptr to point to the data buffer.
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte into A.
    pla

    ; Call resolved device write routine.
    jsr dev_call
    rts
.endproc
