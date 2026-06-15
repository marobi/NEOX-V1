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
;   No gate may be held across sched_yield. Console input waits
;   block on WAIT_CONSOLE, empty pipe reads block on WAIT_PIPE_READ,
;   and full pipe writes block on WAIT_PIPE_WRITE; file_io_gate is
;   released before the blocked task enters sched_yield.
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

.include "debug.inc"
.include "syscall.inc"
.include "fd.inc"
.include "process.inc"
.include "pipe.inc"

.export ksys_io_init
.export ksys_read
.export ksys_console_read_blocking
.export ksys_write
.export ksys_close
.export ksys_dup
.export ksys_dup2
.export ksys_pipe

.import file_io_gate_init
.import proc_gate_init
.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_phase
.import active_pid

.import rp_console_read_start
.import rp_console_read_finish
.import rp_console_write_finish

.import fd_resolve_read
.import fd_resolve_write
.import fd_read
.import fd_write
.import fd_close
.import open_pipe
.import fd_dup
.import fd_dup2
.import pipe_create

.import proc_set_wait
.import sched_yield

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

; Non-zero while the current gate-protected read dispatch is known
; to target the console device. Used to convert console EAGAIN into
; WAIT_CONSOLE without accidentally blocking pipe EAGAIN here.
ksys_rw_is_console:
    .res 1

; Non-zero while the current gate-protected read/write dispatch is
; known to target a pipe. ksys_rw_pipe_idx stores the pipe table index
; used as WAIT_PIPE_READ / WAIT_PIPE_WRITE wait_object.
ksys_rw_is_pipe:
    .res 1

ksys_rw_pipe_idx:
    .res 1

; Per-PID read/write syscall argument snapshot.
;
; Read/write syscalls receive X/Y -> rw_args in the caller context.
; The complete argument block is copied immediately at syscall entry
; while IRQs are masked, before file_io_gate_acquire can block/yield.
; Later FD/backend code must use only this per-PID snapshot, never
; dereference the caller rw_args pointer after a scheduler boundary.
ksys_rw_fd_by_pid:
    .res MAX_PROCS

ksys_rw_buf_lo_by_pid:
    .res MAX_PROCS

ksys_rw_buf_hi_by_pid:
    .res MAX_PROCS

ksys_rw_len_lo_by_pid:
    .res MAX_PROCS

ksys_rw_len_hi_by_pid:
    .res MAX_PROCS

; Short-lived entry scratch used only while IRQs are masked during
; argument-block snapshot. It is not live across yield.
ksys_rw_entry_lo:
    .res 1

ksys_rw_entry_hi:
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
; ksys_console_read_blocking
;
; Submit a console read request and wait for RP completion.
;
; Current implementation polls until RP completion. It does not
; call sched_yield and therefore does not violate the gate rule.
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
; Polling only; no sched_yield while file_io_gate is owned.
; ------------------------------------------------------------

.proc ksys_console_write_wait
@wait:
    jsr rp_console_write_finish
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
; ksys_console_read_wait
;
; Wait for an async RP console read to complete.
; Polling only; no sched_yield while file_io_gate is owned.
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
; Kernel-side syscall wrapper for read(fd, buf, len).
; ------------------------------------------------------------

.proc ksys_read
    ; Snapshot the complete caller rw_args block immediately at
    ; syscall entry.  Do not keep only a pointer: file_io_gate_acquire
    ; may block/yield, and the caller's context/address view is not a
    ; valid late-dereference boundary in a preemptive kernel.
    php
    sei
    stx ksys_rw_entry_lo
    sty ksys_rw_entry_hi

    lda ksys_rw_entry_lo
    sta io_ptr
    lda ksys_rw_entry_hi
    sta io_ptr+1

    ldx active_pid

    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_by_pid,x

    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi_by_pid,x

    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi_by_pid,x
    plp
    ; The user-side syscall macro masks IRQs only while it loads
    ; X/Y and enters the kernel. Re-enable after the argument block
    ; has been copied; file_io_gate itself is the syscall serializer.
    cli

@retry_gate:
    jsr file_io_gate_acquire
    bcs @gate_acquired

    lda #DBG_FILE_IO_READ_ACQ_FAIL
    sta file_io_gate_phase
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_READ_ACQ
    sta file_io_gate_phase

    ; Copy the per-PID syscall-entry snapshot into gate-protected
    ; module scratch. From here until release, these scratch values are
    ; owned by the current file_io_gate holder.
    ldx active_pid
    lda ksys_rw_fd_by_pid,x
    sta ksys_rw_fd_tmp
    lda ksys_rw_buf_lo_by_pid,x
    sta ksys_rw_buf_lo
    lda ksys_rw_buf_hi_by_pid,x
    sta ksys_rw_buf_hi
    lda ksys_rw_len_lo_by_pid,x
    sta ksys_rw_len_lo
    lda ksys_rw_len_hi_by_pid,x
    sta ksys_rw_len_hi

    ; FD/backend layer expects io_ptr to point to caller buffer.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ; Classify the backend before dispatching. fd_read may return
    ; EAGAIN for console or pipe. The syscall layer converts only
    ; those known backends into blocking waits; all other EAGAIN
    ; returns remain normal syscall failures.
    stz ksys_rw_is_console
    stz ksys_rw_is_pipe
    lda #PIPE_NONE
    sta ksys_rw_pipe_idx

    ldy ksys_rw_fd_tmp
    jsr fd_resolve_read
    bcc @read_resolve_ok
    jmp @read_resolve_fail

@read_resolve_ok:
    cmp #OBJ_DEVICE
    beq @class_device

    cmp #OBJ_PIPE
    beq @class_pipe

    bra @read_call

@class_device:
    cpy #DEV_CONSOLE
    bne @read_call

    lda #$01
    sta ksys_rw_is_console
    bra @read_call

@class_pipe:
    ; X = open object from fd_resolve_read.
    lda open_pipe,x
    sta ksys_rw_pipe_idx
    lda #$01
    sta ksys_rw_is_pipe

@read_call:
    lda #DBG_FILE_IO_READ_CALL
    sta file_io_gate_phase

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi
    jsr fd_read
    bcc @read_success

    ; Console backend reports EAGAIN when the console owner has no
    ; input available. Pipe read reports EAGAIN when the pipe is empty
    ; and writers are still present. Convert only those known backend
    ; cases into blocking waits, release file_io_gate, yield, and retry
    ; the original syscall from the per-PID snapshot after wake.
    cpy #EAGAIN
    bne @read_fail

    lda ksys_rw_is_console
    bne @wait_console

    lda ksys_rw_is_pipe
    bne @wait_pipe_read

    bra @read_fail

@wait_console:
    lda #DBG_FILE_IO_READ_WAIT_CONSOLE
    sta file_io_gate_phase

    lda #WAIT_CONSOLE
    ldy #$00
    bra @block_read

@wait_pipe_read:
    lda #DBG_FILE_IO_READ_WAIT_PIPE
    sta file_io_gate_phase

    lda #WAIT_PIPE_READ
    ldy ksys_rw_pipe_idx

@block_read:
    php
    sei

    ldx active_pid
    jsr proc_set_wait

    lda #DBG_FILE_IO_READ_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    ; Keep IRQs masked for the immediate scheduler handoff.  sched_yield
    ; converts this continuation into an RTI frame with I cleared, so the
    ; resumed task continues with IRQs enabled.
    pla                         ; discard saved P byte
    jsr sched_yield
    jmp @retry_gate

@read_success:
    pha
    phx

    lda #DBG_FILE_IO_READ_RET
    sta file_io_gate_phase

    lda #DBG_FILE_IO_READ_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    plx
    pla
    clc
    rts

@read_fail:
    phy

    lda #DBG_FILE_IO_READ_RET
    sta file_io_gate_phase

    lda #DBG_FILE_IO_READ_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    ply
    sec
    rts

@read_resolve_fail:
    phy

    lda #DBG_FILE_IO_READ_REL
    sta file_io_gate_phase
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
    ; Snapshot the complete caller rw_args block immediately at
    ; syscall entry, before file_io_gate_acquire can block/yield.
    php
    sei
    stx ksys_rw_entry_lo
    sty ksys_rw_entry_hi

    lda ksys_rw_entry_lo
    sta io_ptr
    lda ksys_rw_entry_hi
    sta io_ptr+1

    ldx active_pid

    ldy #rw_args::fd
    lda (io_ptr),y
    sta ksys_rw_fd_by_pid,x

    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta ksys_rw_buf_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rw_buf_hi_by_pid,x

    ldy #rw_args::len
    lda (io_ptr),y
    sta ksys_rw_len_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rw_len_hi_by_pid,x
    plp
    ; The user-side syscall macro masks IRQs only while it loads
    ; X/Y and enters the kernel. Re-enable after the argument block
    ; has been copied; file_io_gate itself is the syscall serializer.
    cli

@retry_gate:
    jsr file_io_gate_acquire
    bcs @gate_acquired

    lda #DBG_FILE_IO_WRITE_ACQ_FAIL
    sta file_io_gate_phase
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_WRITE_ACQ
    sta file_io_gate_phase

    ; Copy the per-PID syscall-entry snapshot into gate-protected
    ; module scratch. From here until release, these scratch values are
    ; owned by the current file_io_gate holder.
    ldx active_pid
    lda ksys_rw_fd_by_pid,x
    sta ksys_rw_fd_tmp
    lda ksys_rw_buf_lo_by_pid,x
    sta ksys_rw_buf_lo
    lda ksys_rw_buf_hi_by_pid,x
    sta ksys_rw_buf_hi
    lda ksys_rw_len_lo_by_pid,x
    sta ksys_rw_len_lo
    lda ksys_rw_len_hi_by_pid,x
    sta ksys_rw_len_hi

    ; FD/backend layer expects io_ptr to point to caller buffer.
    lda ksys_rw_buf_lo
    sta io_ptr
    lda ksys_rw_buf_hi
    sta io_ptr+1

    ; Classify pipe writes before dispatch. fd_write may return
    ; EAGAIN for a full pipe with zero bytes written. Only known pipe
    ; EAGAIN is converted into WAIT_PIPE_WRITE.
    stz ksys_rw_is_pipe
    lda #PIPE_NONE
    sta ksys_rw_pipe_idx

    ldy ksys_rw_fd_tmp
    jsr fd_resolve_write
    bcc @write_resolve_ok
    jmp @write_resolve_fail

@write_resolve_ok:
    cmp #OBJ_PIPE
    bne @write_call

    ; X = open object from fd_resolve_write.
    lda open_pipe,x
    sta ksys_rw_pipe_idx
    lda #$01
    sta ksys_rw_is_pipe

@write_call:
    lda #DBG_FILE_IO_WRITE_CALL
    sta file_io_gate_phase

    ldy ksys_rw_fd_tmp
    lda ksys_rw_len_lo
    ldx ksys_rw_len_hi
    jsr fd_write
    bcc @write_success

    cpy #EAGAIN
    bne @write_fail

    lda ksys_rw_is_pipe
    beq @write_fail

@wait_pipe_write:
    lda #DBG_FILE_IO_WRITE_WAIT_PIPE
    sta file_io_gate_phase

    php
    sei

    lda #WAIT_PIPE_WRITE
    ldy ksys_rw_pipe_idx
    ldx active_pid
    jsr proc_set_wait

    lda #DBG_FILE_IO_WRITE_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    ; Keep IRQs masked for the immediate scheduler handoff. sched_yield
    ; converts this continuation into an RTI frame with I cleared, so the
    ; resumed task continues with IRQs enabled.
    pla                         ; discard saved P byte
    jsr sched_yield
    jmp @retry_gate

@write_success:
    pha
    phx

    lda #DBG_FILE_IO_WRITE_RET
    sta file_io_gate_phase

    lda #DBG_FILE_IO_WRITE_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    plx
    pla
    clc
    rts

@write_fail:
    phy

    lda #DBG_FILE_IO_WRITE_RET
    sta file_io_gate_phase

    lda #DBG_FILE_IO_WRITE_REL
    sta file_io_gate_phase
    jsr file_io_gate_release

    ply
    sec
    rts

@write_resolve_fail:
    phy

    lda #DBG_FILE_IO_WRITE_REL
    sta file_io_gate_phase
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

    lda #DBG_FILE_IO_CLOSE_ACQ_FAIL
    sta file_io_gate_phase
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_CLOSE_ACQ
    sta file_io_gate_phase
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

    lda #DBG_FILE_IO_DUP_ACQ_FAIL
    sta file_io_gate_phase
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_DUP_ACQ
    sta file_io_gate_phase
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

    lda #DBG_FILE_IO_DUP2_ACQ_FAIL
    sta file_io_gate_phase
    ply
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_DUP2_ACQ
    sta file_io_gate_phase
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

    lda #DBG_FILE_IO_PIPE_ACQ_FAIL
    sta file_io_gate_phase
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda #DBG_FILE_IO_PIPE_ACQ
    sta file_io_gate_phase

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
