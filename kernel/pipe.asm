; ============================================================
; pipe.asm
; NEOX - anonymous pipe core
; ca65 / W65C02
;
; Pipe backend policy:
;   - 6502-only pipe buffer
;   - pipe_read remains a nonblocking primitive
;   - ksys_read converts empty+writers EAGAIN into WAIT_PIPE_READ
;   - EOF when PIPE_STATE_WRITE_OPEN is clear
;   - EPIPE when PIPE_STATE_READ_OPEN is clear
;   - short write when buffer becomes full
;   - ksys_write converts full+readers EAGAIN into WAIT_PIPE_WRITE
; ============================================================

.setcpu "65C02"

.include "fd.inc"
.include "pipe.inc"
.include "syscall.inc"
.include "process.inc"

.export pipe_init_tables
.export pipe_read
.export pipe_write
.export pipe_close_endpoint

.export pipe_create
.export pipe_create_between_fd

.import fd_alloc_open
.import fd_free_open
.import fd_alloc_fd_current
.import fd_attach_current
.import fd_detach_current
.import fd_init_open
.import fd_check_free_pid_fd
.import fd_attach_pid_fd_read
.import fd_attach_pid_fd_write

.import pipe_state
.import pipe_head
.import pipe_tail
.import pipe_count
.import pipe_buf

.import open_pipe
.import open_pipe_mode

.importzp pipe_ptr
.importzp pipe_buf_ptr

.import file_io_gate_acquire
.import file_io_gate_release
.import scheduler_wake_one
.import mul8u

.segment "KERN_BSS"

; ------------------------------------------------------------
; Pipe-private scratch
;
; These variables are protected by file_io_gate.
;
; Rules:
;   - valid only while file_io_gate is held
;   - never live across sched_yield
;   - never live across a call into another backend subsystem
;   - pipe_read / pipe_write are nonblocking primitives
;
; This intentionally matches the fd.asm style: subsystem-private
; scratch under a subsystem lock, instead of stack-frame state.
; ------------------------------------------------------------

pipe_obj:           .res 1      ; pair read open object
pipe_idx:           .res 1      ; pipe table index
pipe_mode:          .res 1      ; pair write object / close mode or wait reason

pipe_req_lo:        .res 1      ; requested byte count low / temporary errno
pipe_req_hi:        .res 1      ; requested byte count high

pipe_done_lo:       .res 1      ; completed byte count, always 0..PIPE_BUF_SIZE

.segment "KERN_TEXT"

.assert (MAX_PIPES * PIPE_BUF_SIZE) <= $10000, error, "configured pipe storage exceeds 16-bit address range"

; ------------------------------------------------------------
; pipe_set_buf_base
;
; Input:
;   X = pipe index
;
; Output:
;   pipe_buf_ptr = pipe_buf + X * PIPE_BUF_SIZE
;
; Clobbers:
;   A, flags
;
; Preserves:
;   X, Y
;
; Notes:
;   Uses mul8u so PIPE_BUF_SIZE remains configurable.
; ------------------------------------------------------------

.proc pipe_set_buf_base
    phx

    txa
    ldx #PIPE_BUF_SIZE
    jsr mul8u

    clc
    adc #<pipe_buf
    sta pipe_buf_ptr

    txa
    adc #>pipe_buf
    sta pipe_buf_ptr+1

    plx
    rts
.endproc

; ------------------------------------------------------------
; pipe_init_tables
;
; Clears pipe table and open-object pipe metadata.
;
; Return:
;   C clear
;
; Clobbers: A, X
; ------------------------------------------------------------

.proc pipe_init_tables

    ldx #$00
@clear_pipes:
    stz pipe_state,x
    stz pipe_head,x
    stz pipe_tail,x
    stz pipe_count,x
    inx
    cpx #MAX_PIPES
    bne @clear_pipes

    ldx #$00
@clear_open:
    lda #PIPE_NONE
    sta open_pipe,x
    stz open_pipe_mode,x
    inx
    cpx #OPEN_MAX
    bne @clear_open

    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_alloc_pair
;
; Allocate and initialize one complete pipe backend pair.
;
; Caller:
;   must hold file_io_gate
;
; Return:
;   C clear:
;       A = pipe index
;       X = read open object
;       Y = write open object
;
;   C set:
;       Y = errno
;
; Notes:
;   This routine owns all common open-object, pipe-table, endpoint
;   initialization, and pre-attachment rollback work.
;
;   pipe_obj / pipe_mode / pipe_idx are used as protected scratch:
;       pipe_obj  = read open object
;       pipe_mode = write open object
;       pipe_idx  = pipe index
; ------------------------------------------------------------

.proc pipe_alloc_pair
    lda #PIPE_NONE
    sta pipe_obj
    sta pipe_mode
    sta pipe_idx

    jsr fd_alloc_open
    bcc @read_obj_ok
    rts

@read_obj_ok:
    stx pipe_obj

    lda #OBJ_PIPE
    ldy #FD_FLAG_READ
    jsr fd_init_open

    jsr fd_alloc_open
    bcc @write_obj_ok

    sty pipe_req_lo
    ldx pipe_obj
    jsr fd_free_open
    ldy pipe_req_lo
    sec
    rts

@write_obj_ok:
    stx pipe_mode

    lda #OBJ_PIPE
    ldy #FD_FLAG_WRITE
    jsr fd_init_open

    jsr pipe_alloc
    bcc @pipe_ok

    sty pipe_req_lo

    ldx pipe_mode
    jsr fd_free_open

    ldx pipe_obj
    jsr fd_free_open

    ldy pipe_req_lo
    sec
    rts

@pipe_ok:
    sta pipe_idx

    lda pipe_obj
    ldx pipe_idx
    ldy #PIPE_END_READ
    jsr pipe_endpoint_init

    lda pipe_mode
    ldx pipe_idx
    ldy #PIPE_END_WRITE
    jsr pipe_endpoint_init

    lda pipe_idx
    ldx pipe_obj
    ldy pipe_mode
    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_release_pair
;
; Roll back a complete, unattached pipe pair.
;
; Input:
;   X = read open object
;   Y = write open object
;
; Caller:
;   must hold file_io_gate
;
; Return:
;   C clear
; ------------------------------------------------------------

.proc pipe_release_pair
    phx

    tya
    pha
    jsr pipe_close_endpoint

    pla
    tax
    jsr fd_free_open

    pla
    pha
    jsr pipe_close_endpoint

    pla
    tax
    jmp fd_free_open
.endproc

; ------------------------------------------------------------
; pipe_create
;
; Create an anonymous pipe for active_pid.
;
; Return:
;   C clear = success
;             A = read fd
;             X = write fd
;
;   C set   = failure
;             Y = errno
;
; Stack frame while active:
;   $0101,S = errno
;   $0102,S = read open object
;   $0103,S = write open object
;   $0104,S = read fd
;   $0105,S = write fd
; ------------------------------------------------------------

.proc pipe_create
    lda #PIPE_NONE
    pha
    pha
    pha
    pha

    lda #EIO
    pha

    jsr pipe_alloc_pair
    bcc @pair_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@pair_ok:
    tsx
    lda pipe_obj
    sta $0102,x

    lda pipe_mode
    sta $0103,x

    jsr fd_alloc_fd_current
    bcc @read_fd_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_pair

@read_fd_ok:
    tya
    tsx
    sta $0104,x

    ldy $0104,x
    lda $0102,x
    tax
    lda #FD_FLAG_READ
    jsr fd_attach_current

    jsr fd_alloc_fd_current
    bcc @write_fd_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_read_fd

@write_fd_ok:
    tya
    tsx
    sta $0105,x

    ldy $0105,x
    lda $0103,x
    tax
    lda #FD_FLAG_WRITE
    jsr fd_attach_current

    tsx
    lda $0104,x
    pha

    lda $0105,x
    pha

    pla
    tax

    pla
    tay

    pla
    pla
    pla
    pla
    pla

    tya
    clc
    rts

@fail_read_fd:
    tsx
    lda $0104,x
    jsr fd_detach_current

@fail_pair:
    tsx
    lda $0102,x
    pha

    lda $0103,x
    tay

    pla
    tax
    jsr pipe_release_pair

@fail_frame:
    tsx
    ldy $0101,x

    pla
    pla
    pla
    pla
    pla

    sec
    rts
.endproc

; ------------------------------------------------------------
; pipe_create_between_fd
;
; Kernel-only static wiring helper.
;
; Input:
;   A = reader PID
;   X = writer PID
;   Y = fd number to install in both processes
;
; Return:
;   C clear = success
;   C set   = failure, Y = errno
; ------------------------------------------------------------

.proc pipe_create_between_fd
    pha
    phx
    phy
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ply
    plx
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ply
    plx
    pla

    jsr pipe_create_between_fd_inner

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
; pipe_create_between_fd_inner
;
; Input:
;   A = reader PID
;   X = writer PID
;   Y = common fd
;
; Caller:
;   must hold file_io_gate
;
; Stack frame:
;   $0101,S = errno
;   $0102,S = write open object
;   $0103,S = read open object
;   $0104,S = common fd
;   $0105,S = writer PID
;   $0106,S = reader PID
; ------------------------------------------------------------

.proc pipe_create_between_fd_inner
    pha
    phx
    phy

    lda #PIPE_NONE
    pha
    pha

    lda #EIO
    pha

    tsx
    lda $0106,x
    cmp $0105,x
    bne @pids_ok

    lda #EINVAL
    sta $0101,x
    jmp @fail_frame

@pids_ok:
    ldy $0104,x
    lda $0106,x
    tax
    jsr fd_check_free_pid_fd
    bcc @reader_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@reader_fd_free:
    tsx
    ldy $0104,x
    lda $0105,x
    tax
    jsr fd_check_free_pid_fd
    bcc @writer_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@writer_fd_free:
    jsr pipe_alloc_pair
    bcc @pair_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@pair_ok:
    tsx
    lda pipe_mode
    sta $0102,x

    lda pipe_obj
    sta $0103,x

    ldy $0104,x
    lda $0103,x
    pha

    lda $0106,x
    plx
    jsr fd_attach_pid_fd_read
    bcc @read_attached

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@read_attached:
    tsx
    ldy $0104,x
    lda $0102,x
    pha

    lda $0105,x
    plx
    jsr fd_attach_pid_fd_write
    bcc @success

    tya
    tsx
    sta $0101,x
    jmp @fail_frame

@success:
    pla
    pla
    pla
    pla
    pla
    pla

    clc
    rts

@fail_frame:
    tsx
    ldy $0101,x

    pla
    pla
    pla
    pla
    pla
    pla

    sec
    rts
.endproc

; ------------------------------------------------------------
; pipe_alloc
;
; Allocate a pipe table entry.
;
; Caller:
;   must hold file_io_gate
;
; Return:
;   C clear, A = pipe index
;   C set,   Y = ENOMEM
;
; Clobbers: A, X, Y
; ------------------------------------------------------------

.proc pipe_alloc
    ldx #$00

@scan:
    lda pipe_state,x
    beq @found

    inx
    cpx #MAX_PIPES
    bne @scan

    ldy #ENOMEM
    sec
    rts

@found:
    lda #PIPE_STATE_USED
    sta pipe_state,x

    stz pipe_head,x
    stz pipe_tail,x
    stz pipe_count,x

    txa
    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_free
;
; Free a pipe table entry.
;
; Input:
;   A = pipe index
;
; Caller:
;   must hold file_io_gate
;
; Return:
;   C clear
;
; Clobbers: A, X
; ------------------------------------------------------------

.proc pipe_free
    tax

    stz pipe_state,x
    stz pipe_head,x
    stz pipe_tail,x
    stz pipe_count,x

    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_endpoint_init
;
; Input:
;   A = open object
;   X = pipe index
;   Y = PIPE_END_READ or PIPE_END_WRITE
;
; Caller:
;   file_io_gate held
;
; Return:
;   C clear
;
; Clobbers:
;   A, X, flags
; ------------------------------------------------------------

.proc pipe_endpoint_init
    phx                         ; save pipe index
    tax                         ; X = open object

    pla                         ; A = pipe index
    sta open_pipe,x

    tya
    sta open_pipe_mode,x

    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_resolve_endpoint
;
; Resolve and validate one pipe endpoint.
;
; Input:
;   A = required endpoint mode
;   X = open object index
;
; Return:
;   C clear:
;       X = pipe index
;       pipe_idx = pipe index
;
;   C set:
;       Y = EBADF
;
; Caller:
;   must hold file_io_gate
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_resolve_endpoint
    cmp open_pipe_mode,x
    bne @bad_endpoint

    lda open_pipe,x
    cmp #PIPE_NONE
    beq @bad_endpoint

    sta pipe_idx
    tax

    lda pipe_state,x
    beq @bad_endpoint

    clc
    rts

@bad_endpoint:
    ldy #EBADF
    sec
    rts
.endproc

; ------------------------------------------------------------
; pipe_close_endpoint
;
; Close pipe endpoint effects.
;
; Input:
;   A = open object index
;
; Return:
;   C clear
;
; Locking:
;   file_io_gate protects pipe-private scratch and pipe tables.
;
; Notes:
;   - This does not touch proc_fd_obj/proc_fd_flags.
;   - FD layer owns refcounts and open-object lifetime.
;   - If the last writer closes while readers are blocked on an
;     empty pipe, wake them so they can retry and observe EOF.
;   - If the last reader closes while writers are blocked on a full
;     pipe, wake them so they can retry and observe EPIPE.
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_close_endpoint
    tax

    lda open_pipe,x
    cmp #PIPE_NONE
    bne @have_pipe

    clc
    rts

@have_pipe:
    sta pipe_idx

    lda open_pipe_mode,x
    sta pipe_mode

    ; Detach the final open-object reference from its endpoint.
    lda #PIPE_NONE
    sta open_pipe,x
    stz open_pipe_mode,x

    ; PIPE_END_READ/WRITE use the same bit values as the corresponding
    ; pipe_state endpoint-presence flags.
    lda pipe_mode
    cmp #PIPE_END_READ
    beq @valid_mode

    cmp #PIPE_END_WRITE
    bne @maybe_free

@valid_mode:
    ldx pipe_idx

    lda pipe_state,x
    and pipe_mode
    beq @maybe_free

    ; Clear the endpoint-presence bit selected by pipe_mode.
    lda pipe_mode
    eor #$FF
    and pipe_state,x
    sta pipe_state,x

    ; Closing the read end wakes writers for EPIPE.
    ; Closing the write end wakes readers for data/EOF.
    lda pipe_mode
    cmp #PIPE_END_READ
    beq @wake_writers

    lda #WAIT_PIPE_READ
    bra @wake_all

@wake_writers:
    lda #WAIT_PIPE_WRITE

@wake_all:
    sta pipe_mode

@wake_next:
    lda pipe_mode
    ldy pipe_idx
    jsr scheduler_wake_one
    bcc @wake_next

@maybe_free:
    ldx pipe_idx
    lda pipe_state,x
    bne @done

    txa
    jsr pipe_free

@done:
    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_read
;
; Read from a pipe endpoint.
;
; Input:
;   Y        = open object index
;   pipe_ptr = destination buffer
;   A/X      = requested length, low/high
;
; Return:
;   C clear:
;       A/X = bytes read
;       A/X = 0 means EOF when no writers exist
;
;   C set:
;       Y = errno
;
; Nonblocking semantics:
;   empty + writers present -> EAGAIN
;   empty + no writers      -> EOF / 0 bytes
;
; Locking:
;   file_io_gate protects pipe-private scratch and pipe tables.
;
; Important:
;   pipe-private scratch is safe because ksys_io owns file_io_gate
;   before dispatching into the pipe backend.
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_read
    ; Zero-length read succeeds immediately. This check uses only
    ; the incoming registers and does not touch shared scratch.
    cpx #$00
    bne @save_inputs

    cmp #$00
    bne @save_inputs

    lda #$00
    tax
    clc
    rts

@save_inputs:
    ; Preserve call inputs before populating pipe-private scratch.
    pha                         ; requested length low
    phx                         ; requested length high
    phy                         ; open object


    ; file_io_gate is already held by the syscall wrapper.
    ply                         ; Y = open object

    plx
    stx pipe_req_hi

    pla
    sta pipe_req_lo

    ; Resolve and validate the read endpoint.
    tya
    tax
    lda #PIPE_END_READ
    jsr pipe_resolve_endpoint
    bcc @state_ok

    rts

@state_ok:
    ; Empty pipe:
    ;   writers present -> EAGAIN
    ;   no writers      -> EOF
    lda pipe_count,x
    bne @can_read

    lda pipe_state,x
    and #PIPE_STATE_WRITE_OPEN
    bne @err_eagain


    lda #$00
    tax
    clc
    rts

@can_read:
    stz pipe_done_lo

    ; Resolve this pipe's 64-byte buffer base once for the call.
    jsr pipe_set_buf_base

@read_loop:
    ; Stop when requested length has been reached.
    ;
    ; If req_hi != 0, the pipe buffer will empty first because
    ; PIPE_BUF_SIZE is currently 64 bytes.
    lda pipe_req_hi
    bne @check_available

    lda pipe_done_lo
    cmp pipe_req_lo
    beq @done

@check_available:
    lda pipe_count,x
    beq @done

    ; Read one byte from pipe buffer[tail] into user buffer[done].
    ldy pipe_tail,x
    lda (pipe_buf_ptr),y

    ldy pipe_done_lo
    sta (pipe_ptr),y

    ; Advance tail.
    lda pipe_tail,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_tail,x

    dec pipe_count,x

    ; done++. One call can transfer at most PIPE_BUF_SIZE bytes,
    ; so the one-byte counter cannot wrap.
    inc pipe_done_lo
    bra @read_loop

@done:
    ; If at least one byte was read, wake one blocked writer.
    ; The backend can return at most PIPE_BUF_SIZE bytes, so X is zero.
    lda pipe_done_lo
    beq @return_done

    pha
    lda #WAIT_PIPE_WRITE
    ldy pipe_idx
    jsr scheduler_wake_one
    pla

@return_done:
    ldx #$00
    clc
    rts

@err_eagain:

    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; pipe_write
;
; Write to a pipe endpoint.
;
; Input:
;   Y        = open object index
;   pipe_ptr = source buffer
;   A/X      = requested length, low/high
;
; Return:
;   C clear:
;       A/X = bytes written
;       short write is possible when pipe fills after progress
;
;   C set:
;       Y = errno
;
; Nonblocking semantics:
;   no readers                -> EPIPE
;   full + zero bytes written -> EAGAIN
;   full + some bytes written -> short success
;
; Locking:
;   file_io_gate protects pipe-private scratch and pipe tables.
;
; Important:
;   pipe-private scratch is safe because ksys_io owns file_io_gate
;   before dispatching into the pipe backend.
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_write
    ; Zero-length write succeeds immediately. This check uses only
    ; the incoming registers and does not touch shared scratch.
    cpx #$00
    bne @save_inputs

    cmp #$00
    bne @save_inputs

    lda #$00
    tax
    clc
    rts

@save_inputs:
    ; Preserve call inputs before populating pipe-private scratch.
    pha                         ; requested length low
    phx                         ; requested length high
    phy                         ; open object


    ; file_io_gate is already held by the syscall wrapper.
    ply                         ; Y = open object

    plx
    stx pipe_req_hi

    pla
    sta pipe_req_lo

    ; Resolve and validate the write endpoint.
    tya
    tax
    lda #PIPE_END_WRITE
    jsr pipe_resolve_endpoint
    bcc @state_ok

    rts

@state_ok:
    ; Broken pipe: no readers.
    lda pipe_state,x
    and #PIPE_STATE_READ_OPEN
    bne @can_start

    jmp @err_epipe

@can_start:
    stz pipe_done_lo

    ; Resolve this pipe's 64-byte buffer base once for the call.
    jsr pipe_set_buf_base

@write_loop:
    ; Stop when requested length has been reached.
    ;
    ; If req_hi != 0, the pipe buffer will fill first because
    ; PIPE_BUF_SIZE is currently 64 bytes.
    lda pipe_req_hi
    bne @check_space

    lda pipe_done_lo
    cmp pipe_req_lo
    beq @done

@check_space:
    lda pipe_count,x
    cmp #PIPE_BUF_SIZE
    bne @space_available

    ; Full pipe.
    ; If some progress was made, return a short write.
    lda pipe_done_lo
    bne @done

    ; Full with zero progress: nonblocking would-block.
    jmp @err_eagain

@space_available:
    ; Write one byte from user buffer[done] to pipe buffer[head].
    ldy pipe_done_lo
    lda (pipe_ptr),y

    ldy pipe_head,x
    sta (pipe_buf_ptr),y

    ; Advance head.
    lda pipe_head,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_head,x

    inc pipe_count,x

    ; done++. One call can transfer at most PIPE_BUF_SIZE bytes,
    ; so the one-byte counter cannot wrap.
    inc pipe_done_lo
    bra @write_loop

@done:
    ; If at least one byte was written, wake one blocked reader.
    ; The backend can return at most PIPE_BUF_SIZE bytes, so X is zero.
    lda pipe_done_lo
    beq @return_done

    pha
    lda #WAIT_PIPE_READ
    ldy pipe_idx
    jsr scheduler_wake_one
    pla

@return_done:
    ldx #$00
    clc
    rts

@err_eagain:

    ldy #EAGAIN
    sec
    rts

@err_epipe:

    ldy #EPIPE
    sec
    rts
.endproc
