; ============================================================
; neox_write.asm
; NEOX libneox - cc65 public neox_write implementation
;
; Purpose:
;   Implements the compiler-neutral public neox_write() function directly at
;   the cc65 ABI boundary. The function receives normal C arguments, builds
;   the fixed NEOX rw_args block in process-private BSS, executes SYS_WRITE,
;   stores the transferred count through written_out when non-NULL, removes
;   the stacked cc65 parameters, and returns an 8-bit NEOX status code.
;
; Public C declaration:
;   neox_status_t neox_write(
;       neox_fd_t fd,
;       const void* buffer,
;       neox_size_t requested,
;       neox_size_t* written_out);
;
; cc65 entry convention for this fixed-argument function:
;   A/X       = written_out pointer (rightmost argument)
;   (c_sp)+0  = requested low
;   (c_sp)+1  = requested high
;   (c_sp)+2  = buffer pointer low
;   (c_sp)+3  = buffer pointer high
;   (c_sp)+4  = fd
;
; Return:
;   A = NEOX status (0 on success, errno on failure)
;   X = 0
;
; Notes:
;   - The syscall block and saved output pointer are process-private.
;   - NEOX currently permits one execution thread per process context, so the
;     fixed call state cannot be used concurrently within one process.
;   - Task 6 uses descriptor I/O only; this file never accesses BIOS/simple I/O.
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_write

.importzp c_sp
.importzp ptr1
.import incsp5

NEOX_WRITE_STACK_REQUESTED_LO = 0
NEOX_WRITE_STACK_REQUESTED_HI = 1
NEOX_WRITE_STACK_BUFFER_LO    = 2
NEOX_WRITE_STACK_BUFFER_HI    = 3
NEOX_WRITE_STACK_FD           = 4

.segment "C_BSS"

; First six bytes are exactly struct rw_args from syscall.inc.
neox_write_args:
    .res RW_ARGS_SIZE

neox_write_written_ptr:
    .res 2

neox_write_transferred:
    .res 2

neox_write_status:
    .res 1

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_write
;
; Purpose:
;   Implements public neox_write() using the ordinary cc65 C argument ABI.
;
; Input:
;   A/X and c_sp as documented in the file header.
;
; Return:
;   A = NEOX status.
;   X = 0.
;
; Clobbers:
;   A, X, Y, ptr1, processor flags.
; ------------------------------------------------------------
.proc _neox_write
    ; Save the rightmost C argument before reusing A/X.
    sta neox_write_written_ptr
    stx neox_write_written_ptr+1

    ; Build the kernel rw_args block from the remaining cc65 arguments.
    ldy #NEOX_WRITE_STACK_FD
    lda (c_sp),y
    sta neox_write_args+rw_args::fd
    stz neox_write_args+rw_args::reserved

    ldy #NEOX_WRITE_STACK_BUFFER_LO
    lda (c_sp),y
    sta neox_write_args+rw_args::buf_ptr
    iny
    lda (c_sp),y
    sta neox_write_args+rw_args::buf_ptr+1

    ldy #NEOX_WRITE_STACK_REQUESTED_LO
    lda (c_sp),y
    sta neox_write_args+rw_args::len
    iny
    lda (c_sp),y
    sta neox_write_args+rw_args::len+1

    stz neox_write_transferred
    stz neox_write_transferred+1

    ; Use the same fixed syscall ABI as the validated assembly callers.
    sei
    ldx #<neox_write_args
    ldy #>neox_write_args
    jsr sys_write
    bcs @failed

    sta neox_write_transferred
    stx neox_write_transferred+1
    stz neox_write_status
    bra @store_count

@failed:
    tya
    sta neox_write_status

@store_count:
    ; A NULL written_out pointer is explicitly allowed by the public API.
    lda neox_write_written_ptr
    ora neox_write_written_ptr+1
    beq @return

    lda neox_write_written_ptr
    sta ptr1
    lda neox_write_written_ptr+1
    sta ptr1+1

    lda neox_write_transferred
    sta (ptr1)
    ldy #1
    lda neox_write_transferred+1
    sta (ptr1),y

@return:
    ; The callee removes fd (1), buffer (2), and requested (2): five bytes.
    ; incsp5/addysp preserves A and X, so load the C return value first.
    lda neox_write_status
    ldx #0
    jmp incsp5
.endproc
