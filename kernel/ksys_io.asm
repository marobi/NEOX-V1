; ============================================================
; ksys_io.asm
; NEOX - kernel-owned file/FD/pipe/console syscall services
;
; Layering:
;   syscall_table.asm only jumps here through kernel.inc entries.
;   This file owns syscall-level serialization for FD/open-object,
;   pipe, and console dispatch paths through file_io_gate.
;
; Gate policy:
;   file_io_gate protects:
;     - ksys_read / ksys_write / ksys_close / ksys_pipe
;     - dup / dup2
;     - FD table, open-object table, pipe table and buffers
;     - console device dispatch
;
;   Current console and pipe waits do not retain file_io_gate across
;   the scheduler blocking transition. Console input blocks on
;   WAIT_CONSOLE, empty pipe reads
;   block on WAIT_PIPE_READ, and full pipe writes block on
;   WAIT_PIPE_WRITE; file_io_gate is released before those waits. Generic
;   RP file operations retain file_io_gate while blocked in WAIT_RP.
;
; Calling convention from syscall stubs:
;   X/Y -> rw_args block for read/write
;
; Return convention:
;   C clear = success
;             A/X = result where applicable
;
;   C set   = failure
;             Y = errno
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "fd.inc"
.include "process.inc"
.include "mailbox.inc"

.export ksys_io_init
.export ksys_read
.export ksys_write
.export ksys_close
.export ksys_dup
.export ksys_dup2
.export ksys_pipe

.import file_io_gate_init
.import proc_gate_init
.import file_io_gate_acquire
.import file_io_gate_release

.import rp_fs_exec

.import fd_resolve_read
.import fd_resolve_write
.import fd_read
.import fd_write
.import fd_close
.import open_pipe
.import fd_dup
.import fd_dup2
.import pipe_create
.import open_file_handle

.import sched_block_current

.importzp io_ptr

.segment "KERN_BSS"

; ------------------------------------------------------------
; ksys_io private scratch
;
; Protected by:
;   file_io_gate
;
; Rules:
;   - valid only while file_io_gate is owned by active_pid
;   - not live across sched_yield
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

; Local EAGAIN conversion selected during descriptor classification.
; A zero reason means that EAGAIN must be returned to the caller.
ksys_rw_wait_reason:
    .res 1

ksys_rw_wait_object:
    .res 1

.segment "BSS"

; Process-private read/write syscall argument pointer. Each MMU context owns
; its copy, so the pointer remains stable while FILE_IO acquisition blocks.
ksys_rw_args_lo:
    .res 1

ksys_rw_args_hi:
    .res 1


.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_io_init
; ------------------------------------------------------------

.proc ksys_io_init
    ; Initialize all currently defined sleepable syscall gates.
    ; proc_gate is generated now but process syscalls are routed to it later.
    jsr file_io_gate_init
    jmp proc_gate_init
.endproc




; ------------------------------------------------------------
; ksys_io_block
;
; Block the active process for a local console or pipe wait.
;
; Input:
;   A = wait reason
;   Y = wait object
;
; Caller:
;   owns file_io_gate
;
; Behavior:
;   - preserves the wait reason/object across gate release
;   - releases file_io_gate
;   - enters the scheduler-owned blocking transition
;   - resumes at the instruction following the JSR when woken
;
; Notes:
;   WAIT_CONSOLE and WAIT_PIPE_* cannot complete synchronously inside
;   sched_block_current, so this helper normally does not return until
;   the process has been woken and rescheduled.
; ------------------------------------------------------------

.proc ksys_io_block
    pha
    phy

    jsr file_io_gate_release

    ply
    pla
    jmp sched_block_current
.endproc


; ------------------------------------------------------------
; ksys_read
;
; Kernel-side syscall wrapper for read(fd, buf, len).
; ------------------------------------------------------------

.proc ksys_read
    ; Save the caller argument pointer in this process context before gate
    ; acquisition can block. Other processes cannot access this private copy.
    stx ksys_rw_args_lo
    sty ksys_rw_args_hi

@retry_gate:
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ; Restore the caller argument pointer in the caller's active context.
    lda ksys_rw_args_lo
    sta io_ptr
    lda ksys_rw_args_hi
    sta io_ptr+1

    ; Decode local dispatch fields once while file_io_gate is owned.
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

    ; Classify and validate the descriptor. Files are submitted directly to
    ; the generic RP request while console and pipe behavior remains local.
    stz ksys_rw_wait_reason
    stz ksys_rw_wait_object

    ldy ksys_rw_fd_tmp
    jsr fd_resolve_read
    bcc @read_resolve_ok
    jmp @read_fail

@read_resolve_ok:
    cmp #OBJ_FILE
    beq @read_file

    cmp #OBJ_DEVICE
    beq @class_device

    cmp #OBJ_PIPE
    beq @class_pipe

    ldy #ENODEV
    jmp @read_fail

@read_file:
    ; io_ptr still points to the original rw_args block. The kernel supplies
    ; the trusted RP handle; the RP decodes buffer and length in caller context.
    lda open_file_handle,x
    tax
    lda #RP_FS_OP_READ
    ldy #$00
    jsr rp_fs_exec
    bcc @read_success
    jmp @read_fail

@class_device:
    cpy #DEV_CONSOLE
    bne @read_call

    lda #WAIT_CONSOLE
    sta ksys_rw_wait_reason
    bra @read_call

@class_pipe:
    ; X = open object from fd_resolve_read.
    lda open_pipe,x
    sta ksys_rw_wait_object

    lda #WAIT_PIPE_READ
    sta ksys_rw_wait_reason

@read_call:
    ; Local console/pipe backends retain their existing ABI.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi
    jsr fd_read
    bcc @read_success

    cpy #EAGAIN
    bne @read_fail

    lda ksys_rw_wait_reason
    beq @read_fail

    ldy ksys_rw_wait_object
    jsr ksys_io_block
    jmp @retry_gate

@read_success:
    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@read_fail:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts

.endproc

; ------------------------------------------------------------
; ksys_write
;
; Kernel-side syscall wrapper for write(fd, buf, len).
; ------------------------------------------------------------

.proc ksys_write
    ; Save the caller argument pointer in this process context before gate
    ; acquisition can block. Other processes cannot access this private copy.
    stx ksys_rw_args_lo
    sty ksys_rw_args_hi

@retry_gate:
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ; Restore and decode the caller argument block in its active context.
    lda ksys_rw_args_lo
    sta io_ptr
    lda ksys_rw_args_hi
    sta io_ptr+1

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

    stz ksys_rw_wait_reason
    stz ksys_rw_wait_object

    ldy ksys_rw_fd_tmp
    jsr fd_resolve_write
    bcc @write_resolve_ok
    jmp @write_fail

@write_resolve_ok:
    cmp #OBJ_FILE
    beq @write_file

    cmp #OBJ_PIPE
    beq @class_pipe

    cmp #OBJ_DEVICE
    beq @write_call

    ldy #ENODEV
    jmp @write_fail

@write_file:
    ; Keep io_ptr on rw_args and submit the trusted RP handle.
    lda open_file_handle,x
    tax
    lda #RP_FS_OP_WRITE
    ldy #$00
    jsr rp_fs_exec
    bcc @write_success
    jmp @write_fail

@class_pipe:
    ; X = open object from fd_resolve_write.
    lda open_pipe,x
    sta ksys_rw_wait_object

    lda #WAIT_PIPE_WRITE
    sta ksys_rw_wait_reason

@write_call:
    ; Local console/pipe backends retain their existing ABI.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi
    jsr fd_write
    bcc @write_success

    cpy #EAGAIN
    bne @write_fail

    lda ksys_rw_wait_reason
    beq @write_fail

    ldy ksys_rw_wait_object
    jsr ksys_io_block
    jmp @retry_gate

@write_success:
    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@write_fail:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts

.endproc

; ------------------------------------------------------------
; ksys_close
;
; Kernel-side syscall wrapper for close(fd).
; ------------------------------------------------------------

.proc ksys_close
    pha
    jsr file_io_gate_acquire
    bcs @gate_acquired

    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    pla

    jsr fd_close

    php
    pha
    phx
    phy

    jsr file_io_gate_release

    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; ksys_dup
; ------------------------------------------------------------

.proc ksys_dup
    pha
    jsr file_io_gate_acquire
    bcs @gate_acquired

    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    pla

    jsr fd_dup

    php
    pha
    phx
    phy

    jsr file_io_gate_release

    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; ksys_dup2
; ------------------------------------------------------------

.proc ksys_dup2
    pha
    phy
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ply
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ply
    pla

    jsr fd_dup2

    php
    pha
    phx
    phy

    jsr file_io_gate_release

    ply
    plx
    pla
    plp
    rts
.endproc

; ------------------------------------------------------------
; ksys_pipe
;
; Create anonymous pipe for current process.
; ------------------------------------------------------------

.proc ksys_pipe
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:

    jsr pipe_create

    php
    pha
    phx
    phy

    jsr file_io_gate_release

    ply
    plx
    pla
    plp
    rts
.endproc
