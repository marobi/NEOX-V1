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
.include "syscall.inc"
.include "lock.inc"

.export pipe_init_tables
.export pipe_alloc_locked
.export pipe_free_locked
.export pipe_endpoint_init_locked
.export pipe_read
.export pipe_write
.export pipe_close_endpoint

.export pipe_create
.export pipe_create_between_fd

.import fd_lock
.import current_pid

.import fd_alloc_open_locked
.import fd_free_open_locked
.import fd_alloc_fd_current_locked
.import fd_attach_current_locked
.import fd_detach_current_locked
.import fd_init_open_locked
.import fd_check_free_pid_fd_locked
.import fd_attach_pid_fd_read_locked
.import fd_attach_pid_fd_write_locked

.import pipe_lock
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

.segment "KERN_TEXT"

; ------------------------------------------------------------
; pipe_set_buf_ptr
;
; Input:
;   X = pipe index
;   A = byte offset within pipe buffer
;
; Output:
;   pipe_buf_ptr = pipe_buf + X * 64 + offset
;
; Requires:
;   PIPE_BUF_SIZE = 64
;
; Clobbers:
;   A, Y, flags
;
; Preserves:
;   X
; ------------------------------------------------------------

.proc pipe_set_buf_ptr
    ; Save inputs.
    pha                         ; offset
    phx                         ; pipe index

    ; --------------------------------------------------------
    ; Low base:
    ;   low = <pipe_buf + ((pipe_index & 3) * 64)
    ;
    ; The low-byte carry must be preserved because pipe_buf
    ; may not be page-aligned.
    ; --------------------------------------------------------

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

    ; Save carry from low-byte base add in Y.
    ldy #$00
    bcc @no_low_carry
    iny

@no_low_carry:
    ; --------------------------------------------------------
    ; High base:
    ;   high = >pipe_buf + (pipe_index / 4) + low_carry
    ;
    ; For 64-byte buffers, every 4 pipes crosses one page:
    ;   pipe 0..3 -> +0 pages
    ;   pipe 4..7 -> +1 page
    ;   pipe 8..11 -> +2 pages
    ; --------------------------------------------------------

    pla                         ; A = pipe index
    pha                         ; keep pipe index for PLX later

    lsr
    lsr
    clc
    adc #>pipe_buf

    cpy #$00
    beq @store_high_base
    ina

@store_high_base:
    sta pipe_buf_ptr+1

    ; Restore original X.
    plx

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
    stz pipe_lock

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
;   - fd_lock is held while FD/open-object state is allocated.
;   - pipe_lock is held only while pipe table/endpoint state is touched.
;   - pipe_close_endpoint is called only when pipe_lock is not held.
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

    LOCK_ACQUIRE fd_lock

    ; --------------------------------------------------------
    ; Allocate and initialize read endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open_locked
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
    jsr fd_init_open_locked

    ; --------------------------------------------------------
    ; Allocate and initialize write endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open_locked
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
    jsr fd_init_open_locked

    ; --------------------------------------------------------
    ; Allocate pipe table entry and attach endpoint metadata.
    ; --------------------------------------------------------

    LOCK_ACQUIRE pipe_lock

    jsr pipe_alloc_locked
    bcc @pipe_ok

    tya
    tsx
    sta $0101,x                 ; errno

    LOCK_RELEASE pipe_lock
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
    jsr pipe_endpoint_init_locked

    ; write endpoint: A = write object, X = pipe index, Y = write mode
    tsx
    lda $0103,x                 ; write open object
    pha

    lda $0104,x                 ; pipe index
    tax

    pla                         ; A = write open object
    ldy #PIPE_END_WRITE
    jsr pipe_endpoint_init_locked

    LOCK_RELEASE pipe_lock

    ; --------------------------------------------------------
    ; Allocate read fd and attach it.
    ; --------------------------------------------------------

    jsr fd_alloc_fd_current_locked
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
    jsr fd_attach_current_locked

    ; --------------------------------------------------------
    ; Allocate write fd and attach it.
    ; --------------------------------------------------------

    jsr fd_alloc_fd_current_locked
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
    jsr fd_attach_current_locked

    ; --------------------------------------------------------
    ; Success.
    ; --------------------------------------------------------

    LOCK_RELEASE fd_lock

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
    ; fd_lock is still held.
    tsx
    lda $0105,x
    jsr fd_detach_current_locked

@fail_endpoints:
    ; No pipe_lock is held here.
    ; pipe_close_endpoint acquires pipe_lock internally.

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
    jsr fd_free_open_locked

@fail_readobj:
    tsx
    lda $0102,x                 ; read open object
    cmp #$ff
    beq @fail_fdlock

    tax
    jsr fd_free_open_locked

@fail_fdlock:
    LOCK_RELEASE fd_lock

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
    LOCK_ACQUIRE fd_lock

    ; --------------------------------------------------------
    ; Validate reader fd is free.
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd
    lda $0107,x                 ; reader PID
    tax
    jsr fd_check_free_pid_fd_locked
    bcc @reader_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_fd_locked

@reader_fd_free:
    ; --------------------------------------------------------
    ; Validate writer fd is free.
    ; --------------------------------------------------------

    tsx
    ldy $0105,x                 ; common fd
    lda $0106,x                 ; writer PID
    tax
    jsr fd_check_free_pid_fd_locked
    bcc @writer_fd_free

    tya
    tsx
    sta $0101,x
    jmp @fail_fd_locked

@writer_fd_free:
    ; --------------------------------------------------------
    ; Allocate and initialize read endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open_locked
    bcc @read_obj_ok

    tya
    tsx
    sta $0101,x
    jmp @fail_fd_locked

@read_obj_ok:
    txa                         ; A = read open object
    tsx
    sta $0104,x

    lda $0104,x
    tax                         ; X = read open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_READ
    jsr fd_init_open_locked

    ; --------------------------------------------------------
    ; Allocate and initialize write endpoint open object.
    ; --------------------------------------------------------

    jsr fd_alloc_open_locked
    bcc @write_obj_ok

    tya
    tsx
    sta $0101,x

    lda $0104,x                 ; read open object
    tax
    jsr fd_free_open_locked

    jmp @fail_fd_locked

@write_obj_ok:
    txa                         ; A = write open object
    tsx
    sta $0103,x

    lda $0103,x
    tax                         ; X = write open object
    lda #OBJ_PIPE
    ldy #FD_FLAG_WRITE
    jsr fd_init_open_locked

    ; --------------------------------------------------------
    ; Allocate pipe and initialize endpoint metadata.
    ; --------------------------------------------------------

    LOCK_ACQUIRE pipe_lock

    jsr pipe_alloc_locked
    bcc @pipe_ok

    LOCK_RELEASE pipe_lock

    tya
    tsx
    sta $0101,x

    lda $0104,x                 ; read open object
    tax
    jsr fd_free_open_locked

    tsx
    lda $0103,x                 ; write open object
    tax
    jsr fd_free_open_locked

    jmp @fail_fd_locked

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
    jsr pipe_endpoint_init_locked

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
    jsr pipe_endpoint_init_locked

    LOCK_RELEASE pipe_lock

    ; --------------------------------------------------------
    ; Attach read endpoint to reader PID/fd.
    ;
    ; Input to fd_attach_pid_fd_read_locked:
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

    jsr fd_attach_pid_fd_read_locked
    bcc @read_attach_ok

    ; Should be unreachable because fd_lock is still held and the
    ; fd slot was prechecked.
    tya
    tsx
    sta $0101,x
    jmp @fail_fd_locked

@read_attach_ok:
    ; --------------------------------------------------------
    ; Attach write endpoint to writer PID/fd.
    ;
    ; Input to fd_attach_pid_fd_write_locked:
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

    jsr fd_attach_pid_fd_write_locked
    bcc @write_attach_ok

    ; Should be unreachable because fd_lock is still held and the
    ; fd slot was prechecked.
    tya
    tsx
    sta $0101,x
    jmp @fail_fd_locked

@write_attach_ok:
    LOCK_RELEASE fd_lock

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

@fail_fd_locked:
    LOCK_RELEASE fd_lock

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
; pipe_alloc_locked
;
; Allocate a pipe table entry.
;
; Caller:
;   must hold pipe_lock
;
; Return:
;   C clear, A = pipe index
;   C set,   Y = ENOMEM
;
; Clobbers: A, X, Y
; ------------------------------------------------------------

.proc pipe_alloc_locked
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
; pipe_free_locked
;
; Free a pipe table entry.
;
; Input:
;   A = pipe index
;
; Caller:
;   must hold pipe_lock
;
; Return:
;   C clear
;
; Clobbers: A, X
; ------------------------------------------------------------

.proc pipe_free_locked
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
; pipe_endpoint_init_locked
;
; Input:
;   A = open object
;   X = pipe index
;   Y = PIPE_END_READ or PIPE_END_WRITE
;
; Caller:
;   pipe_lock held
;
; Return:
;   C clear
;
; Clobbers:
;   A, X, flags
; ------------------------------------------------------------

.proc pipe_endpoint_init_locked
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
; Input:
;   A = open object index
;
; Return:
;   C clear
;
; Notes:
;   Reentrant: no module-global scratch.
; ------------------------------------------------------------

.proc pipe_close_endpoint
    pha                         ; save open object

    LOCK_ACQUIRE pipe_lock

    pla
    tax                         ; X = open object

    lda open_pipe,x
    cmp #PIPE_NONE
    bne @have_pipe

    LOCK_RELEASE pipe_lock
    clc
    rts

@have_pipe:
    pha                         ; save pipe index

    lda open_pipe_mode,x
    pha                         ; save endpoint mode

    lda #PIPE_NONE
    sta open_pipe,x
    stz open_pipe_mode,x

    pla                         ; A = endpoint mode
    plx                         ; X = pipe index

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
    jsr pipe_free_locked

@done:
    LOCK_RELEASE pipe_lock
    clc
    rts
.endproc

; ------------------------------------------------------------
; pipe_read
;
; Read from a pipe endpoint.
;
; Input:
;   Y            = open object index
;   pipe_ptr     = destination buffer
;   A/X          = requested length, low/high
;
; Return:
;   C clear:
;       A/X = bytes read
;       A/X = 0 means EOF when no writers exist
;
;   C set:
;       Y = errno
;
; Notes:
;   - Reentrant: no module-global call-frame scratch.
;   - Uses CPU stack for call-frame state.
;   - Uses pipe_ptr only for user buffer access.
;   - Uses pipe_buf_ptr only as computed pipe-buffer pointer.
;   - Nonblocking:
;       empty + writers present -> EAGAIN
;       empty + no writers      -> EOF / 0 bytes
;   - Does not yield.
;
; Stack frame after setup:
;   $0101,S = done count
;   $0102,S = requested length high
;   $0103,S = requested length low
;   $0104,S = open object, later replaced by pipe index
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_read
    ; Zero-length read succeeds immediately.
    cpx #$00
    bne @have_len

    cmp #$00
    bne @have_len

    lda #$00
    tax
    clc
    rts

@have_len:
    ; Build stack frame.
    phy                         ; open object
    pha                         ; requested length low
    phx                         ; requested length high
    lda #$00
    pha                         ; done count

    LOCK_ACQUIRE pipe_lock

    ; X = open object.
    tsx
    lda $0104,x
    tax

    lda open_pipe_mode,x
    cmp #PIPE_END_READ
    beq @mode_ok

    jmp @err_ebadf_locked

@mode_ok:
    lda open_pipe,x
    cmp #PIPE_NONE
    bne @pipe_ok

    jmp @err_ebadf_locked

@pipe_ok:
    ; Replace saved open object with pipe index.
    tsx
    sta $0104,x
    tax                         ; X = pipe index

    lda pipe_state,x
    cmp #PIPE_USED
    beq @state_ok

    jmp @err_ebadf_locked

@state_ok:
    lda pipe_count,x
    bne @read_loop

    lda pipe_writers,x
    bne @err_eagain_locked

    ; EOF: empty pipe and no writers.
    LOCK_RELEASE pipe_lock

    ; Drop stack frame.
    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; pipe index/open object

    lda #$00
    tax
    clc
    rts

@read_loop:
    ; Stop if requested length reached.
    tsx
    lda $0102,x                 ; req high
    bne @check_available

    lda $0101,x                 ; done
    cmp $0103,x                 ; req low
    beq @done

@check_available:
    ; X = pipe index.
    tsx
    lda $0104,x
    tax

    lda pipe_count,x
    beq @done

    ; Compute pipe buffer pointer:
    ;   pipe_buf_ptr = pipe_buf + pipe_index * PIPE_BUF_SIZE + tail
    lda pipe_tail,x
    jsr pipe_set_buf_ptr

    ; Load from pipe buffer and store to user buffer[done].
    lda (pipe_buf_ptr)

    tsx
    ldy $0101,x                 ; done
    sta (pipe_ptr),y

    ; X = pipe index.
    tsx
    lda $0104,x
    tax

    ; tail = (tail + 1) & (PIPE_BUF_SIZE - 1)
    lda pipe_tail,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_tail,x

    dec pipe_count,x

    ; done++
    tsx
    inc $0101,x

    bra @read_loop

@done:
    ; Preserve return byte count in X while dropping frame.
    tsx
    lda $0101,x
    tax

    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; pipe index/open object

    txa                         ; A = bytes read
    ldx #$00                    ; high byte = 0
    clc
    rts

@err_ebadf_locked:
    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; open object / pipe index

    ldy #EBADF
    sec
    rts

@err_eagain_locked:
    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; open object / pipe index

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
;   Y            = open object index
;   pipe_ptr     = source buffer
;   A/X          = requested length, low/high
;
; Return:
;   C clear:
;       A/X = bytes written
;       short write is possible when the pipe fills
;
;   C set:
;       Y = errno
;
; Notes:
;   - Reentrant: no module-global call-frame scratch.
;   - Uses CPU stack for call-frame state.
;   - Uses pipe_ptr only for user buffer access.
;   - Uses pipe_buf_ptr only as computed pipe-buffer pointer.
;   - Nonblocking:
;       full + zero bytes written -> EAGAIN
;       full + some bytes written -> short success
;       no readers               -> EPIPE
;   - Does not yield.
;
; Stack frame after setup:
;   $0101,S = done count
;   $0102,S = requested length high
;   $0103,S = requested length low
;   $0104,S = open object, later replaced by pipe index
;
; Clobbers:
;   A, X, Y, flags
; ------------------------------------------------------------

.proc pipe_write
    ; Zero-length write succeeds immediately.
    cpx #$00
    bne @have_len

    cmp #$00
    bne @have_len

    lda #$00
    tax
    clc
    rts

@have_len:
    ; Build stack frame.
    phy                         ; open object
    pha                         ; requested length low
    phx                         ; requested length high
    lda #$00
    pha                         ; done count

    LOCK_ACQUIRE pipe_lock

    ; X = open object.
    tsx
    lda $0104,x
    tax

    lda open_pipe_mode,x
    cmp #PIPE_END_WRITE
    beq @mode_ok

    jmp @err_ebadf_locked

@mode_ok:
    lda open_pipe,x
    cmp #PIPE_NONE
    bne @pipe_ok

    jmp @err_ebadf_locked

@pipe_ok:
    ; Replace saved open object with pipe index.
    tsx
    sta $0104,x
    tax                         ; X = pipe index

    lda pipe_state,x
    cmp #PIPE_USED
    beq @state_ok

    jmp @err_ebadf_locked

@state_ok:
    lda pipe_readers,x
    bne @write_loop

    jmp @err_epipe_locked

@write_loop:
    ; Stop if requested length reached.
    tsx
    lda $0102,x                 ; req high
    bne @check_space

    lda $0101,x                 ; done
    cmp $0103,x                 ; req low
    beq @done

@check_space:
    ; X = pipe index.
    tsx
    lda $0104,x
    tax

    lda pipe_count,x
    cmp #PIPE_BUF_SIZE
    bne @space_available

    ; Full pipe.
    ; If at least one byte was written, return short success.
    tsx
    lda $0101,x                 ; done
    bne @done

    jmp @err_eagain_locked

@space_available:
    ; Compute pipe buffer pointer:
    ;   pipe_buf_ptr = pipe_buf + pipe_index * PIPE_BUF_SIZE + head
    tsx
    lda $0104,x
    tax

    lda pipe_head,x
    jsr pipe_set_buf_ptr

    ; Copy user buffer[done] to current pipe buffer byte.
    tsx
    ldy $0101,x                 ; done
    lda (pipe_ptr),y
    sta (pipe_buf_ptr)

    ; X = pipe index.
    tsx
    lda $0104,x
    tax

    ; head = (head + 1) & (PIPE_BUF_SIZE - 1)
    lda pipe_head,x
    ina
    and #(PIPE_BUF_SIZE - 1)
    sta pipe_head,x

    inc pipe_count,x

    ; done++
    tsx
    inc $0101,x

    bra @write_loop

@done:
    ; Preserve return byte count in X while dropping frame.
    tsx
    lda $0101,x
    tax

    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; pipe index/open object

    txa                         ; A = bytes written
    ldx #$00                    ; high byte = 0
    clc
    rts

@err_ebadf_locked:
    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; open object / pipe index

    ldy #EBADF
    sec
    rts

@err_eagain_locked:
    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; open object / pipe index

    ldy #EAGAIN
    sec
    rts

@err_epipe_locked:
    LOCK_RELEASE pipe_lock

    pla                         ; done
    pla                         ; req high
    pla                         ; req low
    pla                         ; open object / pipe index

    ldy #EPIPE
    sec
    rts
.endproc
