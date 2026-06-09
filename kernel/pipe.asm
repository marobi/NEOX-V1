; ============================================================
; pipe.asm
; NEOX - anonymous pipe core
; ca65 / W65C02
;
; First implementation:
;   - 6502-only pipe buffer
;   - nonblocking read/write
;   - EOF when writers == 0
;   - EPIPE/EIO when readers == 0
;   - short write when buffer becomes full
;
; No scheduler blocking here yet.
; ============================================================

.setcpu "65C02"

.include "fd.inc"
.include "pipe.inc"
.include "debug.inc"
.include "syscall.inc"
.include "lock.inc"

.export pipe_init_tables
.export pipe_alloc
.export pipe_free
.export pipe_endpoint_init
.export pipe_read
.export pipe_write
.export pipe_close_endpoint

.export pipe_create
.export pipe_create_between_fd

.import current_pid

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
.import pipe_readers
.import pipe_writers
.import pipe_buf

.import open_pipe
.import open_pipe_mode

.importzp pipe_ptr
.importzp pipe_buf_ptr

.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_phase

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

pipe_obj:           .res 1      ; open object index
pipe_idx:           .res 1      ; pipe table index
pipe_mode:          .res 1      ; PIPE_END_READ / PIPE_END_WRITE

pipe_req_lo:        .res 1      ; requested byte count low
pipe_req_hi:        .res 1      ; requested byte count high

pipe_done_lo:       .res 1      ; completed byte count low
pipe_done_hi:       .res 1      ; completed byte count high

.segment "KERN_TEXT"

; ------------------------------------------------------------
; pipe_set_buf_ptr
;
; Input:
;   X = pipe index
;   A = byte offset within pipe buffer
;
; Output:
;   pipe_buf_ptr = pipe_buf + X * PIPE_BUF_SIZE + offset
;
; Requires:
;   PIPE_BUF_SIZE = 64
;
; Clobbers:
;   A, Y, flags
;
; Preserves:
;   X
;
; Notes:
;   The low-byte carry is handled explicitly so pipe_buf does
;   not need to be page-aligned.
; ------------------------------------------------------------

.proc pipe_set_buf_ptr
    pha                         ; save offset
    phx                         ; save pipe index

    ; Low byte:
    ;   <pipe_buf + ((pipe_idx & 3) * 64)
    txa
    and #$03
    asl
    asl
    asl
    asl
    asl
    asl
    clc
    adc #<pipe_buf
    sta pipe_buf_ptr

    ; Preserve carry from low-byte base calculation in Y.
    ldy #$00
    bcc @no_low_carry
    iny

@no_low_carry:
    ; High byte:
    ;   >pipe_buf + (pipe_idx / 4) + low_carry
    pla                         ; A = pipe index
    pha                         ; keep for PLX

    lsr
    lsr
    clc
    adc #>pipe_buf

    cpy #$00
    beq @store_high
    ina

@store_high:
    sta pipe_buf_ptr+1

    plx                         ; restore pipe index

    ; Add byte offset.
    pla                         ; A = offset
    clc
    adc pipe_buf_ptr
    sta pipe_buf_ptr

    lda pipe_buf_ptr+1
    adc #$00
    sta pipe_buf_ptr+1

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
    stz pipe_readers,x
    stz pipe_writers,x
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
; pipe_create
;
; Create an anonymous pipe for current_pid.
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
;   $0104,S = pipe index
;   $0105,S = read fd
;   $0106,S = write fd
;
; Notes:
;   - Reentrant: no module-global scratch.
;   - file_io_gate is held while FD/open-object state is allocated.
;   - file_io_gate is held while pipe table/endpoint state is touched.
;   - pipe_close_endpoint expects file_io_gate to be held.
; ------------------------------------------------------------

.proc pipe_create
    ; Allocate local stack frame, initialized to $FF.
    lda #$ff
    pha                         ; write fd
    pha                         ; read fd
    pha                         ; pipe index
    pha                         ; write open object
    pha                         ; read open object
    pha                         ; errno


    ; --------------------------------------------------------
    ; Allocate and initialize read endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open
    bcc @read_obj_ok

    tya
    tsx
    sta $0101,x                 ; errno
    jmp @fail_fdlock

@read_obj_ok:
    txa                         ; A = read open object
    tsx
    sta $0102,x

    lda $0102,x
    tax                         ; X = read open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_READ
    jsr fd_init_open

    ; --------------------------------------------------------
    ; Allocate and initialize write endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open
    bcc @write_obj_ok

    tya
    tsx
    sta $0101,x                 ; errno
    jmp @fail_readobj

@write_obj_ok:
    txa                         ; A = write open object
    tsx
    sta $0103,x

    lda $0103,x
    tax                         ; X = write open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_WRITE
    jsr fd_init_open

    ; --------------------------------------------------------
    ; Allocate pipe table entry and attach endpoint metadata.
    ; --------------------------------------------------------


    jsr pipe_alloc
    bcc @pipe_ok

    tya
    tsx
    sta $0101,x                 ; errno

    jmp @fail_writeobj

@pipe_ok:
    tsx
    sta $0104,x                 ; pipe index

    ; read endpoint: A = read object, X = pipe index, Y = read mode
    lda $0102,x                 ; read open object
    pha

    lda $0104,x                 ; pipe index
    tax

    pla                         ; A = read open object
    ldy #PIPE_END_READ
    jsr pipe_endpoint_init

    ; write endpoint: A = write object, X = pipe index, Y = write mode
    tsx
    lda $0103,x                 ; write open object
    pha

    lda $0104,x                 ; pipe index
    tax

    pla                         ; A = write open object
    ldy #PIPE_END_WRITE
    jsr pipe_endpoint_init


    ; --------------------------------------------------------
    ; Allocate read fd and attach it.
    ; --------------------------------------------------------

    jsr fd_alloc_fd_current
    bcc @read_fd_ok

    tya
    tsx
    sta $0101,x                 ; errno
    jmp @fail_endpoints

@read_fd_ok:
    tya                         ; A = read fd
    tsx
    sta $0105,x

    ; Attach read fd.
    ; Keep X as stack index until Y has been loaded.
    lda $0102,x                 ; read open object
    pha

    ldy $0105,x                 ; read fd

    pla
    tax                         ; X = read open object

    lda #FD_FLAG_READ
    jsr fd_attach_current

    ; --------------------------------------------------------
    ; Allocate write fd and attach it.
    ; --------------------------------------------------------

    jsr fd_alloc_fd_current
    bcc @write_fd_ok

    tya
    tsx
    sta $0101,x                 ; errno
    jmp @fail_readfd

@write_fd_ok:
    tya                         ; A = write fd
    tsx
    sta $0106,x

    ; Attach write fd.
    ; Keep X as stack index until Y has been loaded.
    lda $0103,x                 ; write open object
    pha

    ldy $0106,x                 ; write fd

    pla
    tax                         ; X = write open object

    lda #FD_FLAG_WRITE
    jsr fd_attach_current

    ; --------------------------------------------------------
    ; Success.
    ; --------------------------------------------------------


    ; Save return values above the local frame.
    tsx
    lda $0105,x                 ; read fd
    pha

    lda $0106,x                 ; write fd
    pha

    ; Restore return values first.
    pla
    tax                         ; X = write fd

    pla
    tay                         ; Y = read fd

    ; Drop local frame.
    pla                         ; errno
    pla                         ; read open object
    pla                         ; write open object
    pla                         ; pipe index
    pla                         ; read fd
    pla                         ; write fd

    tya                         ; A = read fd
    clc
    rts

    ; --------------------------------------------------------
    ; Rollback paths.
    ; --------------------------------------------------------

@fail_readfd:
    ; Undo read fd attachment.
    ; file_io_gate is still held.
    tsx
    lda $0105,x
    jsr fd_detach_current

@fail_endpoints:
    ; file_io_gate is held here.
    ; pipe_close_endpoint expects file_io_gate to be held.

    tsx
    lda $0103,x                 ; write open object
    cmp #$ff
    beq @close_read_endpoint

    jsr pipe_close_endpoint

@close_read_endpoint:
    tsx
    lda $0102,x                 ; read open object
    cmp #$ff
    beq @fail_writeobj

    jsr pipe_close_endpoint

@fail_writeobj:
    tsx
    lda $0103,x                 ; write open object
    cmp #$ff
    beq @fail_readobj

    tax
    jsr fd_free_open

@fail_readobj:
    tsx
    lda $0102,x                 ; read open object
    cmp #$ff
    beq @fail_fdlock

    tax
    jsr fd_free_open

@fail_fdlock:

    ; Load errno before dropping frame.
    tsx
    ldy $0101,x

    ; Drop local frame.
    pla                         ; errno
    pla                         ; read open object
    pla                         ; write open object
    pla                         ; pipe index
    pla                         ; read fd
    pla                         ; write fd

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
; Example:
;   A = 2
;   X = 1
;   Y = 3
;
; Result:
;   PID 2 fd 3 = read endpoint
;   PID 1 fd 3 = write endpoint
;
; Return:
;   C clear = success
;   C set   = failure, Y = errno
;
; Notes:
;   - Not a syscall.
;   - Caller should use this during kernel/static task setup.
;   - Same PID is rejected because this helper uses one common fd.
;     Use normal pipe_create for same-process pipes.
; ------------------------------------------------------------

.proc pipe_create_between_fd
    ; This entry-table helper can be called outside ksys_io.asm,
    ; so it acquires file_io_gate itself.
    pha
    phx
    phy
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ; DEBUG-BEGIN: temporary file-io-pipe-link-acq-fail diagnostic
    lda #DBG_FILE_IO_PIPE_LINK_ACQ_FAIL
    sta file_io_gate_phase
    ; DEBUG-END: temporary file-io-pipe-link-acq-fail diagnostic
    ply
    plx
    pla
    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ; DEBUG-BEGIN: temporary file-io-pipe-link-acq diagnostic
    lda #DBG_FILE_IO_PIPE_LINK_ACQ
    sta file_io_gate_phase
    ; DEBUG-END: temporary file-io-pipe-link-acq diagnostic
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

.proc pipe_create_between_fd_inner
    ; Stack frame:
    ;   $0101,x = errno
    ;   $0102,x = pipe index
    ;   $0103,x = write open object
    ;   $0104,x = read open object
    ;   $0105,x = common fd
    ;   $0106,x = writer PID
    ;   $0107,x = reader PID

    pha                         ; reader PID
    phx                         ; writer PID
    phy                         ; common fd

    lda #PIPE_NONE
    pha                         ; read open object

    lda #PIPE_NONE
    pha                         ; write open object

    lda #PIPE_NONE
    pha                         ; pipe index

    lda #EIO
    pha                         ; errno

    ; Reject same PID for this fixed-fd helper.
    tsx
    lda $0107,x                 ; reader PID
    cmp $0106,x                 ; writer PID
    bne @pids_ok

    lda #EINVAL
    sta $0101,x
    jmp @fail_frame

@pids_ok:

    ; --------------------------------------------------------
    ; Validate reader fd is free.
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd
    lda $0107,x                 ; reader PID
    tax
    jsr fd_check_free_pid_fd
    bcc @reader_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_fd

@reader_fd_free:
    ; --------------------------------------------------------
    ; Validate writer fd is free.
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd
    lda $0106,x                 ; writer PID
    tax
    jsr fd_check_free_pid_fd
    bcc @writer_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_fd

@writer_fd_free:
    ; --------------------------------------------------------
    ; Allocate and initialize read endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open
    bcc @read_obj_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_fd

@read_obj_ok:
    txa                         ; A = read open object
    tsx
    sta $0104,x

    lda $0104,x
    tax                         ; X = read open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_READ
    jsr fd_init_open

    ; --------------------------------------------------------
    ; Allocate and initialize write endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open
    bcc @write_obj_ok

    tya
    tsx
    sta $0101,x

    lda $0104,x                 ; read open object
    tax
    jsr fd_free_open

    jmp @fail_fd

@write_obj_ok:
    txa                         ; A = write open object
    tsx
    sta $0103,x

    lda $0103,x
    tax                         ; X = write open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_WRITE
    jsr fd_init_open

    ; --------------------------------------------------------
    ; Allocate pipe and initialize endpoint metadata.
    ; --------------------------------------------------------


    jsr pipe_alloc
    bcc @pipe_ok


    tya
    tsx
    sta $0101,x

    lda $0104,x                 ; read open object
    tax
    jsr fd_free_open

    tsx
    lda $0103,x                 ; write open object
    tax
    jsr fd_free_open

    jmp @fail_fd

@pipe_ok:
    tsx
    sta $0102,x                 ; pipe index returned in A

    ; read endpoint metadata:
    ;   A = read open object
    ;   X = pipe index
    ;   Y = PIPE_END_READ

    lda $0104,x                 ; read open object
    pha

    lda $0102,x                 ; pipe index
    tax

    pla                         ; A = read open object
    ldy #PIPE_END_READ
    jsr pipe_endpoint_init

    ; write endpoint metadata:
    ;   A = write open object
    ;   X = pipe index
    ;   Y = PIPE_END_WRITE

    tsx
    lda $0103,x                 ; write open object
    pha

    lda $0102,x                 ; pipe index
    tax

    pla                         ; A = write open object
    ldy #PIPE_END_WRITE
    jsr pipe_endpoint_init


    ; --------------------------------------------------------
    ; Attach read endpoint to reader PID/fd.
    ;
    ; Input to fd_attach_pid_fd_read:
    ;   A = PID
    ;   X = open object
    ;   Y = fd
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd

    lda $0104,x                 ; read open object
    pha

    lda $0107,x                 ; reader PID
    plx                         ; X = read open object

    jsr fd_attach_pid_fd_read
    bcc @read_attach_ok

    ; Should be unreachable because file_io_gate is still held and the
    ; fd slot was prechecked.
    tya
    tsx
    sta $0101,x
    jmp @fail_fd

@read_attach_ok:
    ; --------------------------------------------------------
    ; Attach write endpoint to writer PID/fd.
    ;
    ; Input to fd_attach_pid_fd_write:
    ;   A = PID
    ;   X = open object
    ;   Y = fd
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd

    lda $0103,x                 ; write open object
    pha

    lda $0106,x                 ; writer PID
    plx                         ; X = write open object

    jsr fd_attach_pid_fd_write
    bcc @write_attach_ok

    ; Should be unreachable because file_io_gate is still held and the
    ; fd slot was prechecked.
    tya
    tsx
    sta $0101,x
    jmp @fail_fd

@write_attach_ok:

    ; Drop stack frame.
    pla                         ; errno
    pla                         ; pipe index
    pla                         ; write open object
    pla                         ; read open object
    pla                         ; common fd
    pla                         ; writer PID
    pla                         ; reader PID

    clc
    rts

@fail_fd:

@fail_frame:
    tsx
    lda $0101,x
    tay

    ; Drop stack frame.
    pla                         ; errno
    pla                         ; pipe index
    pla                         ; write open object
    pla                         ; read open object
    pla                         ; common fd
    pla                         ; writer PID
    pla                         ; reader PID

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
    lda #PIPE_USED
    sta pipe_state,x

    stz pipe_head,x
    stz pipe_tail,x
    stz pipe_count,x

    lda #$01
    sta pipe_readers,x
    sta pipe_writers,x

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
    stz pipe_readers,x
    stz pipe_writers,x

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
;   - This is still nonblocking. Wake calls can be added later
;     when syscall-layer blocking is implemented.
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_close_endpoint
    sta pipe_obj


    ldx pipe_obj

    lda open_pipe,x
    cmp #PIPE_NONE
    bne @have_pipe

    clc
    rts

@have_pipe:
    sta pipe_idx

    lda open_pipe_mode,x
    sta pipe_mode

    ; Detach open object from pipe metadata.
    lda #PIPE_NONE
    sta open_pipe,x
    stz open_pipe_mode,x

    ldx pipe_idx

    lda pipe_mode
    cmp #PIPE_END_READ
    bne @check_write

    lda pipe_readers,x
    beq @maybe_free

    dec pipe_readers,x
    bra @maybe_free

@check_write:
    cmp #PIPE_END_WRITE
    bne @maybe_free

    lda pipe_writers,x
    beq @maybe_free

    dec pipe_writers,x

@maybe_free:
    lda pipe_readers,x
    ora pipe_writers,x
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
    ply
    sty pipe_obj

    plx
    stx pipe_req_hi

    pla
    sta pipe_req_lo

    ; Validate endpoint mode.
    ldx pipe_obj

    lda open_pipe_mode,x
    cmp #PIPE_END_READ
    beq @mode_ok

    jmp @err_ebadf

@mode_ok:
    ; Resolve open object -> pipe index.
    lda open_pipe,x
    cmp #PIPE_NONE
    bne @pipe_ok

    jmp @err_ebadf

@pipe_ok:
    sta pipe_idx
    tax                         ; X = pipe index

    lda pipe_state,x
    cmp #PIPE_USED
    beq @state_ok

    jmp @err_ebadf

@state_ok:
    ; Empty pipe:
    ;   writers present -> EAGAIN
    ;   no writers      -> EOF
    lda pipe_count,x
    bne @can_read

    lda pipe_writers,x
    bne @err_eagain


    lda #$00
    tax
    clc
    rts

@can_read:
    stz pipe_done_lo
    stz pipe_done_hi

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
    ldx pipe_idx

    lda pipe_count,x
    beq @done

    ; Compute source pointer:
    ;   pipe_buf_ptr = pipe buffer base + tail
    lda pipe_tail,x
    jsr pipe_set_buf_ptr

    ; Copy one byte from pipe buffer to user buffer[done].
    ldy #$00
    lda (pipe_buf_ptr),y

    ldy pipe_done_lo
    sta (pipe_ptr),y

    ; Advance tail.
    ldx pipe_idx

    lda pipe_tail,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_tail,x

    dec pipe_count,x

    ; done++
    inc pipe_done_lo
    bne @read_loop

    inc pipe_done_hi
    bra @read_loop

@done:
    ; Save return value before restoring backend ABI registers.
    ; Save pipe_done_* before returning through the backend ABI.
    lda pipe_done_lo
    pha

    lda pipe_done_hi
    pha


    pla
    tax                         ; X = bytes read high

    pla                         ; A = bytes read low
    clc
    rts

@err_ebadf:

    ldy #EBADF
    sec
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
    ply
    sty pipe_obj

    plx
    stx pipe_req_hi

    pla
    sta pipe_req_lo

    ; Validate endpoint mode.
    ldx pipe_obj

    lda open_pipe_mode,x
    cmp #PIPE_END_WRITE
    beq @mode_ok

    jmp @err_ebadf

@mode_ok:
    ; Resolve open object -> pipe index.
    lda open_pipe,x
    cmp #PIPE_NONE
    bne @pipe_ok

    jmp @err_ebadf

@pipe_ok:
    sta pipe_idx
    tax                         ; X = pipe index

    lda pipe_state,x
    cmp #PIPE_USED
    beq @state_ok

    jmp @err_ebadf

@state_ok:
    ; Broken pipe: no readers.
    lda pipe_readers,x
    bne @can_start

    jmp @err_epipe

@can_start:
    stz pipe_done_lo
    stz pipe_done_hi

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
    ldx pipe_idx

    lda pipe_count,x
    cmp #PIPE_BUF_SIZE
    bne @space_available

    ; Full pipe.
    ; If some progress was made, return a short write.
    lda pipe_done_lo
    ora pipe_done_hi
    bne @done

    ; Full with zero progress: nonblocking would-block.
    jmp @err_eagain

@space_available:
    ; Compute destination pointer:
    ;   pipe_buf_ptr = pipe buffer base + head
    lda pipe_head,x
    jsr pipe_set_buf_ptr

    ; Copy one byte from user buffer[done] to pipe buffer.
    ldy pipe_done_lo
    lda (pipe_ptr),y

    ldy #$00
    sta (pipe_buf_ptr),y

    ; Advance head.
    ldx pipe_idx

    lda pipe_head,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_head,x

    inc pipe_count,x

    ; done++
    inc pipe_done_lo
    bne @write_loop

    inc pipe_done_hi
    bra @write_loop

@done:
    ; Save return value before restoring backend ABI registers.
    ; Save pipe_done_* before returning through the backend ABI.
    lda pipe_done_lo
    pha

    lda pipe_done_hi
    pha


    pla
    tax                         ; X = bytes written high

    pla                         ; A = bytes written low
    clc
    rts

@err_ebadf:

    ldy #EBADF
    sec
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
