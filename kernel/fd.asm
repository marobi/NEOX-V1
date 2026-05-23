; ============================================================
; fd.asm
; NEOX - file descriptor / open object handling
;
; Model:
;   process fd table -> open object table -> backend device
;
; This file provides:
;   - global open-object initialization
;   - per-process fd initialization
;   - fd_attach primitive (core building block)
;
; Design rules:
;   - FD table is per-process
;   - open objects are system-wide and reference counted
;   - fd_attach is the only place that increments refcount
; ============================================================

.setcpu "65C02"

.include "fd.inc"
.include "lock.inc"
.include "math8.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"

.export fd_resolve_read
.export fd_resolve_write

.export fd_init_tables
.export fd_init_process
.export fd_close_process
.export fd_read
.export fd_write
.export fd_close
.export fd_dup
.export fd_dup2

.export fd_alloc_open
.export fd_free_open
.export fd_init_open
.export fd_alloc_fd_current
.export fd_attach_current
.export fd_detach_current
.export fd_check_free_pid_fd
.export fd_attach_pid_fd_read
.export fd_attach_pid_fd_write

;---------------------------------------------------
.import fd_lock

.import current_pid

.importzp io_ptr

.import proc_fd_obj
.import proc_fd_flags

.import open_type
.import open_refcnt
.import open_flags
.import open_dev

.import dev_resolve_op
.import dev_call

.importzp fd_ptr

.importzp dev_ptr

.importzp pipe_ptr
.import pipe_read
.import pipe_write
.import pipe_close_endpoint

.segment "KERN_BSS"

; ------------------------------------------------------------
; FD-private scratch
;
; These variables are private to fd.asm.
;
; Rules:
;   - valid only inside FD subsystem routines
;   - protected by fd_lock where FD/open-object tables are modified
;   - never ABI-visible
;   - never monitor/RP-visible
;   - not stored in shared_state.asm
;   - not stored in zero page because they are not pointers
;
; fd_ptr remains in ZEROPAGE because it is used for
; indirect-indexed addressing: (fd_ptr),Y.
; ------------------------------------------------------------

fd_pid_tmp:
    .res 1              ; PID currently being inspected/modified

fd_index_tmp:
    .res 1              ; per-process fd number

fd_obj_tmp:
    .res 1              ; open-object index

fd_flags_tmp:
    .res 1              ; FD_FLAG_READ / FD_FLAG_WRITE / CLOEXEC mask

fd_closeproc_pid:
    .res 1              ; PID used while closing all FDs for a process

fd_closeproc_fd:
    .res 1              ; fd iterator used by fd_close_process

.segment "KERN_TEXT"

; ------------------------------------------------------------
; fd_alloc_open
;
; Caller:
;   fd_lock held
;
; Output:
;   C clear = success, X = open object index
;   C set   = failure, Y = ENOMEM
; ------------------------------------------------------------

.proc fd_alloc_open
    ldx #0

@scan:
    cpx #OPEN_MAX
    beq @full

    lda open_type,x
    bne @next

    lda open_refcnt,x
    bne @next

    clc
    rts

@next:
    inx
    bra @scan

@full:
    ldy #ENOMEM
    sec
    rts
.endproc

; ------------------------------------------------------------
; fd_free_open
;
; Caller:
;   fd_lock held
;
; Input:
;   X = open object index
;
; Output:
;   C clear
; ------------------------------------------------------------

.proc fd_free_open
    stz open_type,x
    stz open_refcnt,x
    stz open_flags,x
    stz open_dev,x
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_init_open
;
; Caller:
;   fd_lock held
;
; Input:
;   X = open object index
;   A = open object type
;   Y = open object flags
;
; Output:
;   C clear
;
; Notes:
;   Refcount remains 0 until an FD is attached.
; ------------------------------------------------------------

.proc fd_init_open
    sta open_type,x
    tya
    sta open_flags,x
    stz open_refcnt,x
    stz open_dev,x
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_attach_current
;
; Caller:
;   fd_lock held
;
; Input:
;   X = open object index
;   Y = fd
;   A = fd flags
;
; Output:
;   C clear
;
; Notes:
;   Uses fd_attach, which increments open_refcnt.
; ------------------------------------------------------------

.proc fd_attach_current
    sta fd_flags_tmp
    txa
    ldx current_pid
    jmp fd_attach
.endproc

; ------------------------------------------------------------
; fd_check_free_pid_fd
;
; Input:
;   X = PID
;   Y = fd
;
; Output:
;   C clear = fd slot is free
;   C set   = failure, Y = errno
;
; Requirements:
;   Caller holds fd_lock.
; ------------------------------------------------------------

.proc fd_check_free_pid_fd
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    cpy #MAX_FDS
    bcc @fd_ok

    ldy #EBADF
    sec
    rts

@fd_ok:
    stx fd_pid_tmp
    sty fd_index_tmp

    ; offset = PID * MAX_FDS
    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; fd_ptr = proc_fd_obj + offset
    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y
    cmp #FD_NONE
    beq @free

    ldy #EMFILE
    sec
    rts

@free:
    ldx fd_pid_tmp
    ldy fd_index_tmp
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_attach_pid_fd_read
;
; Input:
;   A = PID
;   X = open object
;   Y = fd
;
; Output:
;   C clear = success
;   C set   = failure, Y = errno
;
; Requirements:
;   Caller holds fd_lock.
; ------------------------------------------------------------

.proc fd_attach_pid_fd_read
    pha
    lda #FD_FLAG_READ
    sta fd_flags_tmp
    pla
    jmp fd_attach_pid_fd_mode
.endproc

; ------------------------------------------------------------
; fd_attach_pid_fd_write
;
; Input:
;   A = PID
;   X = open object
;   Y = fd
;
; Output:
;   C clear = success
;   C set   = failure, Y = errno
;
; Requirements:
;   Caller holds fd_lock.
; ------------------------------------------------------------

.proc fd_attach_pid_fd_write
    pha
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    pla
    jmp fd_attach_pid_fd_mode
.endproc

; ------------------------------------------------------------
; fd_attach_pid_fd_mode
;
; Internal helper.
;
; Input:
;   A            = PID
;   X            = open object
;   Y            = fd
;   fd_flags_tmp = FD_FLAG_READ or FD_FLAG_WRITE
;
; Requirements:
;   Caller holds fd_lock.
; ------------------------------------------------------------

.proc fd_attach_pid_fd_mode
    sta fd_pid_tmp
    stx fd_obj_tmp
    sty fd_index_tmp

    ldx fd_pid_tmp
    ldy fd_index_tmp
    jsr fd_check_free_pid_fd
    bcc @free

    sec
    rts

@free:
    ldx fd_pid_tmp
    ldy fd_index_tmp
    lda fd_obj_tmp
    jmp fd_attach
.endproc

; ------------------------------------------------------------
; fd_check_perm
;
; Purpose:
;   Check access permission for the current process fd.
;
; Input:
;   fd_index_tmp = fd index
;   A            = required flag mask
;                  FD_FLAG_READ or FD_FLAG_WRITE
;
; Output:
;   C clear = allowed
;   C set   = denied
;             Y = EBADF
;
; Clobbers:
;   A, X, Y, fd_ptr, factor1, factor2, fd_flags_tmp
; ------------------------------------------------------------

.proc fd_check_perm
    sta fd_flags_tmp

    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y
    and fd_flags_tmp
    bne @allowed

    ldy #EBADF
    sec
    rts

@allowed:
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_close_current
;
; Internal helper.
;
; Purpose:
;   Close fd for current_pid while fd_lock is already held.
;
; Input:
;   A = fd
;
; Output:
;   C clear = success
;   C set   = failure, Y = errno
;
; Notes:
;   Does not acquire/release fd_lock.
;   Does not call backend close.
; ------------------------------------------------------------

.proc fd_close_current
    cmp #MAX_FDS
    bcc @fd_ok

    ldy #EBADF
    sec
    rts

@fd_ok:
    sta fd_index_tmp

    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y
    cmp #FD_NONE
    bne @is_open

    ldy #EBADF
    sec
    rts

@is_open:
    tax

    lda #FD_NONE
    sta (fd_ptr),y

    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda #0
    sta (fd_ptr),y

    lda open_refcnt,x
    beq @ok

    dec open_refcnt,x

@ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_detach_current
;
; Caller:
;   fd_lock held
;
; Input:
;   A = fd
;
; Output:
;   C clear = success
;   C set   = failure, Y = errno
;
; Notes:
;   Rollback helper only.
;   It clears current_pid's fd slot and decrements open_refcnt.
;   It does not run backend close effects.
; ------------------------------------------------------------

.proc fd_detach_current
    jmp fd_close_current
.endproc

; ------------------------------------------------------------
; fd_init_tables
;
; Purpose:
;   Initialize the FD subsystem at boot.
;
; Behavior:
;   - clears fd_lock
;   - clears every per-process FD slot for every PID
;   - clears every per-process FD flag slot for every PID
;   - clears all global open-object slots
;   - installs three global console open objects:
;       0 = stdin
;       1 = stdout
;       2 = stderr
;
; Notes:
;   Per-process FD tables are cleared here even for PROC_EMPTY
;   slots. This keeps monitor/ps output deterministic when a PID
;   was not created, for example when task 3 is disabled.
;
;   Refcounts start at 0. They are incremented later by
;   fd_init_process / fd_attach when processes attach their
;   local descriptors to these open objects.
; ------------------------------------------------------------

.proc fd_init_tables
    ; FD subsystem starts unlocked.
    stz fd_lock

    ; --------------------------------------------------------
    ; Clear all per-process FD object slots.
    ;
    ; proc_fd_obj[pid * MAX_FDS + fd] = FD_NONE
    ; for every PID and every FD.
    ; --------------------------------------------------------

    ldx #$00
    lda #FD_NONE

@clear_proc_fd_obj:
    sta proc_fd_obj,x
    inx
    cpx #(MAX_PROCS * MAX_FDS)
    bne @clear_proc_fd_obj

    ; --------------------------------------------------------
    ; Clear all per-process FD flags.
    ;
    ; proc_fd_flags[pid * MAX_FDS + fd] = 0
    ; for every PID and every FD.
    ; --------------------------------------------------------

    ldx #$00
    lda #$00

@clear_proc_fd_flags:
    sta proc_fd_flags,x
    inx
    cpx #(MAX_PROCS * MAX_FDS)
    bne @clear_proc_fd_flags

    ; --------------------------------------------------------
    ; Clear global open-object table.
    ; --------------------------------------------------------

    ldx #$00

@clear_open:
    stz open_type,x
    stz open_refcnt,x
    stz open_flags,x
    stz open_dev,x

    inx
    cpx #OPEN_MAX
    bne @clear_open

    ; --------------------------------------------------------
    ; Install standard global console open objects.
    ;
    ; Refcounts remain 0 here. Per-process fd_attach calls will
    ; increment them.
    ; --------------------------------------------------------

    ; stdin object
    lda #OBJ_DEVICE
    sta open_type+STDIN
    lda #DEV_CONSOLE
    sta open_dev+STDIN

    ; stdout object
    lda #OBJ_DEVICE
    sta open_type+STDOUT
    lda #DEV_CONSOLE
    sta open_dev+STDOUT

    ; stderr object
    lda #OBJ_DEVICE
    sta open_type+STDERR
    lda #DEV_CONSOLE
    sta open_dev+STDERR

    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_attach
;
; Purpose:
;   Attach an open object to one process-local file descriptor.
;
; Input:
;   X            = PID
;   Y            = fd index
;   A            = open object index
;   fd_flags_tmp = per-fd flags to install
;
; Output:
;   C clear = success
;
; Clobbers:
;   A, X, Y, fd_ptr, factor1, factor2
;   fd_pid_tmp, fd_index_tmp, fd_obj_tmp
;
; Requirements:
;   Caller must hold the FD critical section.
;
; Effects:
;   proc_fd_obj[pid][fd]   = open object
;   proc_fd_flags[pid][fd] = fd_flags_tmp
;   open_refcnt[object]++
; ------------------------------------------------------------

.proc fd_attach
    ; Save inputs in local scratch.
    stx fd_pid_tmp
    sty fd_index_tmp
    sta fd_obj_tmp

    ; --------------------------------------------------------
    ; offset = pid * MAX_FDS
    ; --------------------------------------------------------

    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; --------------------------------------------------------
    ; proc_fd_obj[pid][fd] = object
    ; --------------------------------------------------------

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda fd_obj_tmp
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; proc_fd_flags[pid][fd] = fd_flags_tmp
    ; --------------------------------------------------------

    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda fd_flags_tmp
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; open_refcnt[object]++
    ; --------------------------------------------------------

    ldx fd_obj_tmp
    inc open_refcnt,x

    ; Restore useful values for caller/debugging.
    ldx fd_pid_tmp
    ldy fd_index_tmp
    lda fd_obj_tmp

    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_lookup
;
; Input:
;   A = fd
;
; Output:
;   C clear = success
;   X = open object index
;
;   C set = failure
;   Y = errno
;
; Clobbers:
;   A, X, Y, fd_ptr, fd_index_tmp, factor1, factor2
; ------------------------------------------------------------

.proc fd_lookup
    cmp #MAX_FDS
    bcc @fd_ok

    ldy #EBADF
    sec
    rts

@fd_ok:
    sta fd_index_tmp

    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y
    cmp #FD_NONE
    bne @obj_ok

    ldy #EBADF
    sec
    rts

@obj_ok:
    tax
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_close_pid
;
; Internal helper.
;
; Purpose:
;   Close one fd for a specific PID.
;
; Input:
;   X = PID
;   A = fd number
;
; Output:
;   C clear = success
;             A = 0
;             X = 0
;
;   C set   = failure
;             Y = errno
;
; Notes:
;   Owns fd_lock.
;   Backend close, if any, runs outside fd_lock.
; ------------------------------------------------------------

.proc fd_close_pid
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    cmp #MAX_FDS
    bcc @fd_ok

    ldy #EBADF
    sec
    rts

@fd_ok:
    pha                         ; preserve fd across LOCK_ACQUIRE

    LOCK_ACQUIRE fd_lock

    pla

    ; Save PID/fd while table work is active.
    stx fd_pid_tmp
    sta fd_index_tmp

    ; offset = PID * MAX_FDS
    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; fd_ptr = proc_fd_obj + offset
    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ; Get object.
    ldy fd_index_tmp
    lda (fd_ptr),y
    cmp #FD_NONE
    bne @is_open

    LOCK_RELEASE fd_lock

    ldy #EBADF
    sec
    rts

@is_open:
    tax                         ; X = open object

    ; Clear proc_fd_obj[PID][fd].
    lda #FD_NONE
    sta (fd_ptr),y

    ; Clear proc_fd_flags[PID][fd].
    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda #0
    sta (fd_ptr),y

    ; Decrement refcount.
    lda open_refcnt,x
    beq @done

    dec open_refcnt,x
    lda open_refcnt,x
    bne @done

    ; Last reference. Check whether backend close is needed.
    lda open_type,x
    cmp #OBJ_PIPE
    beq @close_pipe

    cmp #OBJ_DEVICE
    beq @close_device

    ; Unknown/simple object type: free generic open slot.
    jsr fd_free_open
    bra @done

@close_pipe:
    ; X = open object.
    ; pipe_close_endpoint acquires pipe_lock internally.
    ; fd_lock -> pipe_lock order is used here and this path must not block.
    phx

    txa
    jsr pipe_close_endpoint

    plx
    jsr fd_free_open

    bra @done

@done:
    LOCK_RELEASE fd_lock
    lda #0
    tax
    clc
    rts

@close_device:
    ; Resolve close op while fd_lock is still held, then snapshot
    ; dev_ptr as an RTS target before releasing fd_lock.
    lda #DEVOP_CLOSE
    jsr dev_resolve_op
    bcc @close_op_ok

    LOCK_RELEASE fd_lock

    lda #0
    tax
    clc
    rts

@close_op_ok:
    ; Push dev_ptr - 1 as RTS target.
    lda dev_ptr
    beq @target_low_zero

    lda dev_ptr+1
    pha

    lda dev_ptr
    sec
    sbc #1
    pha

    bra @target_ready

@target_low_zero:
    lda dev_ptr+1
    sec
    sbc #1
    pha

    lda #$ff
    pha

@target_ready:
    LOCK_RELEASE fd_lock

    rts                         ; tail-call device close backend
.endproc

; ------------------------------------------------------------
; fd_close
;
; Purpose:
;   Close one file descriptor for current_pid.
;
; Input:
;   A = fd number
;
; Output:
;   C clear = success
;             A = 0
;             X = 0
;
;   C set   = failure
;             Y = errno
; ------------------------------------------------------------

.proc fd_close
    ldx current_pid
    jmp fd_close_pid
.endproc

; ------------------------------------------------------------
; fd_init_process
;
; Purpose:
;   Initialize standard descriptors for a newly created process.
;
; Input:
;   X = PID
;
; Notes:
;   May run while scheduler is active.
;   Target PID must not be runnable yet.
;   Owns fd_lock while clearing/attaching descriptors.
; ------------------------------------------------------------

.proc fd_init_process
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    LOCK_ACQUIRE fd_lock

    ; Save PID because fd_attach uses scratch internally.
    stx fd_pid_tmp

    ; offset = PID * MAX_FDS
    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; Clear proc_fd_obj[pid][*].
    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy #0
    lda #FD_NONE

@clear_obj:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_obj

    ; Clear proc_fd_flags[pid][*].
    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy #0
    lda #0

@clear_flags:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_flags

    ; Attach standard descriptors.

    ldx fd_pid_tmp
    lda #FD_FLAG_READ
    sta fd_flags_tmp
    ldy #STDIN
    lda #STDIN
    jsr fd_attach

    ldx fd_pid_tmp
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDOUT
    lda #STDOUT
    jsr fd_attach

    ldx fd_pid_tmp
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDERR
    lda #STDERR
    jsr fd_attach

    LOCK_RELEASE fd_lock

    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_close_process
;
; Purpose:
;   Close all FDs belonging to PID X.
;
; Input:
;   X = PID
;
; Notes:
;   Uses fd_close_pid so all close/refcount behavior is shared.
;   EBADF is ignored because closed slots are expected.
; ------------------------------------------------------------

.proc fd_close_process
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    stx fd_closeproc_pid
    stz fd_closeproc_fd

@loop:
    lda fd_closeproc_fd
    cmp #MAX_FDS
    beq @done

    ldx fd_closeproc_pid
    lda fd_closeproc_fd
    jsr fd_close_pid
    bcc @next

    cpy #EBADF
    beq @next

    sec
    rts

@next:
    inc fd_closeproc_fd
    bra @loop

@done:
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_tail_call_device
;
; Internal helper.
;
; Purpose:
;   Tail-call the device routine currently stored in dev_ptr.
;
; Input:
;   fd_lock is held
;   dev_ptr = target device routine
;   stack contains:
;       saved X length
;       saved A length
;       caller return address
;
; Output:
;   Does not return to fd_read/fd_write.
;   Device routine RTS returns to fd_read/fd_write caller.
;
; Notes:
;   LOCK_RELEASE clobbers A, so A is preserved in Y.
;   dev_ptr is snapshotted onto the stack before fd_lock release.
;   Uses RTS tail-call, not RTI.
; ------------------------------------------------------------

.proc fd_tail_call_device
    ; Restore requested length for backend.
    plx                         ; X = length high
    pla                         ; A = length low
    tay                         ; preserve length low across LOCK_RELEASE

    ; Push dev_ptr - 1 as RTS target while fd_lock is still held.
    lda dev_ptr
    beq @target_low_zero

@target_low_nonzero:
    lda dev_ptr+1
    pha

    lda dev_ptr
    sec
    sbc #1
    pha

    bra @target_ready

@target_low_zero:
    lda dev_ptr+1
    sec
    sbc #1
    pha

    lda #$ff
    pha

@target_ready:
    LOCK_RELEASE fd_lock

    tya                         ; restore A = length low

    rts                         ; tail-call device backend
.endproc

; ------------------------------------------------------------
; fd_resolve_read
;
; Input:
;   Y = fd number
;
; Output:
;   C clear = success
;       X = open object index
;       A = open object type
;       Y = device id, if object is OBJ_DEVICE
;
;   C set = failure
;       Y = errno
;
; Purpose:
;   Validate fd for read and return the open-object metadata.
;
; Notes:
;   Does not call a backend.
;   Does not keep fd_lock held on return.
; ------------------------------------------------------------

.proc fd_resolve_read
    lda #FD_FLAG_READ
    bra fd_resolve_rw
.endproc

; ------------------------------------------------------------
; fd_resolve_write
;
; Input:
;   Y = fd number
;
; Output:
;   C clear = success
;       X = open object index
;       A = open object type
;       Y = device id, if object is OBJ_DEVICE
;
;   C set = failure
;       Y = errno
;
; Purpose:
;   Validate fd for write and return the open-object metadata.
;
; Notes:
;   Does not call a backend.
;   Does not keep fd_lock held on return.
; ------------------------------------------------------------

.proc fd_resolve_write
    lda #FD_FLAG_WRITE
    ; fall through
.endproc

; ------------------------------------------------------------
; fd_resolve_rw
;
; Input:
;   A = required FD flag
;   Y = fd number
;
; Output:
;   C clear = success
;       X = open object index
;       A = open object type
;       Y = device id, if object is OBJ_DEVICE
;
;   C set = failure
;       Y = errno
;
; Locking:
;   Acquires fd_lock only for fd/open-object lookup.
;   Releases fd_lock before returning.
; ------------------------------------------------------------

.proc fd_resolve_rw
    sta fd_flags_tmp

    LOCK_ACQUIRE fd_lock

    ; Resolve fd -> open object.
    tya
    jsr fd_lookup
    bcc @fd_ok

    ; fd_lookup returns errno in Y.
    phy
    LOCK_RELEASE fd_lock
    ply
    sec
    rts

@fd_ok:
    ; Save open object across permission check.
    phx

    lda fd_flags_tmp
    jsr fd_check_perm
    bcc @perm_ok

    ; fd_check_perm returns errno in Y.
    plx                         ; discard saved open object
    phy
    LOCK_RELEASE fd_lock
    ply
    sec
    rts

@perm_ok:
    plx                         ; X = open object

    ; Return object metadata.
    ;
    ; Preserve X across lock release by saving it. Preserve
    ; returned A/Y across LOCK_RELEASE because the macro clobbers A.
    lda open_type,x
    pha

    lda open_dev,x
    tay

    phx
    phy

    LOCK_RELEASE fd_lock

    ply                         ; Y = device id
    plx                         ; X = open object
    pla                         ; A = object type

    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_read
;
; Purpose:
;   FD-layer implementation of read dispatch.
;
; Input:
;   Y      = fd number
;   io_ptr = destination buffer
;   A/X    = requested length, low/high
;
; Output:
;   C clear = success
;             A/X = bytes read
;
;   C set   = failure
;             Y = errno
;
; Flow:
;   fd -> open object -> permission -> object type -> backend
;
; Notes:
;   - FD lookup and permission check are protected by fd_lock.
;   - Device backend is tail-called through dev_ptr.
;   - Pipe backend is called after fd_lock is released.
;   - pipe_ptr is a dedicated ZP pointer for pipe byte transfer.
; ------------------------------------------------------------

.proc fd_read
    ; Preserve requested length.
    pha
    phx

    LOCK_ACQUIRE fd_lock

    ; Resolve fd -> open object.
    tya
    jsr fd_lookup
    bcc @fd_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@fd_ok:
    ; Save open object across permission check.
    phx

    lda #FD_FLAG_READ
    jsr fd_check_perm
    bcc @perm_ok

    plx                         ; discard open object

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@perm_ok:
    plx                         ; X = open object

    lda open_type,x
    cmp #OBJ_PIPE
    beq @pipe_ok

    cmp #OBJ_DEVICE
    beq @device_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    ldy #ENODEV
    sec
    rts

@pipe_ok:
    ; Save open object above saved length.
    txa
    pha

    LOCK_RELEASE fd_lock

    ; Snapshot caller buffer pointer into the pipe-specific ZP ptr.
    lda io_ptr
    sta pipe_ptr
    lda io_ptr+1
    sta pipe_ptr+1

    ; Restore pipe backend arguments.
    pla
    tay                         ; Y = open object

    plx                         ; X = length high
    pla                         ; A = length low

    jmp pipe_read

@device_ok:
    lda #DEVOP_READ
    jsr dev_resolve_op
    bcc @op_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@op_ok:
    jmp fd_tail_call_device
.endproc

; ------------------------------------------------------------
; fd_write
;
; Purpose:
;   FD-layer implementation of write dispatch.
;
; Input:
;   Y      = fd number
;   io_ptr = source buffer
;   A/X    = requested length, low/high
;
; Output:
;   C clear = success
;             A/X = bytes written
;
;   C set   = failure
;             Y = errno
;
; Flow:
;   fd -> open object -> permission -> object type -> backend
;
; Notes:
;   - FD lookup and permission check are protected by fd_lock.
;   - Device backend is tail-called through dev_ptr.
;   - Pipe backend is called after fd_lock is released.
;   - pipe_ptr is a dedicated ZP pointer for pipe byte transfer.
; ------------------------------------------------------------

.proc fd_write
    ; Preserve requested length.
    pha
    phx

    LOCK_ACQUIRE fd_lock

    ; Resolve fd -> open object.
    tya
    jsr fd_lookup
    bcc @fd_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@fd_ok:
    ; Save open object across permission check.
    phx

    lda #FD_FLAG_WRITE
    jsr fd_check_perm
    bcc @perm_ok

    plx                         ; discard open object

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@perm_ok:
    plx                         ; X = open object

    lda open_type,x
    cmp #OBJ_PIPE
    beq @pipe_ok

    cmp #OBJ_DEVICE
    beq @device_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    ldy #ENODEV
    sec
    rts

@pipe_ok:
    ; Save open object above saved length.
    txa
    pha

    LOCK_RELEASE fd_lock

    ; Snapshot caller buffer pointer into the pipe-specific ZP ptr.
    lda io_ptr
    sta pipe_ptr
    lda io_ptr+1
    sta pipe_ptr+1

    ; Restore pipe backend arguments.
    pla
    tay                         ; Y = open object

    plx                         ; X = length high
    pla                         ; A = length low

    jmp pipe_write

@device_ok:
    lda #DEVOP_WRITE
    jsr dev_resolve_op
    bcc @op_ok

    LOCK_RELEASE fd_lock

    plx
    pla
    sec
    rts

@op_ok:
    jmp fd_tail_call_device
.endproc

; ------------------------------------------------------------
; fd_get_flags_current
;
; Purpose:
;   Fetch proc_fd_flags[current_pid][fd_index_tmp].
;
; Input:
;   fd_index_tmp = fd index
;
; Output:
;   A = fd flags
;
; Clobbers:
;   A, Y, fd_ptr, factor1, factor2
; ------------------------------------------------------------

.proc fd_get_flags_current
    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y

    rts
.endproc

; ------------------------------------------------------------
; fd_find_free_current
;
; Purpose:
;   Find the lowest free fd slot for current_pid.
;
; Output:
;   C clear = found
;             Y = free fd index
;
;   C set   = no free descriptor
;             Y = EMFILE
;
; Clobbers:
;   A, Y, fd_ptr, factor1, factor2
; ------------------------------------------------------------

.proc fd_find_free_current
    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy #0

@scan:
    cpy #MAX_FDS
    beq @full

    lda (fd_ptr),y
    cmp #FD_NONE
    beq @found

    iny
    bra @scan

@found:
    clc
    rts

@full:
    ldy #EMFILE
    sec
    rts
.endproc

; ------------------------------------------------------------
; fd_alloc_fd_current
;
; Caller:
;   fd_lock held
;
; Output:
;   C clear = success, Y = fd
;   C set   = failure, Y = EMFILE
; ------------------------------------------------------------

.proc fd_alloc_fd_current
    jmp fd_find_free_current
.endproc

; ------------------------------------------------------------
; fd_dup
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
;
; Notes:
;
; ------------------------------------------------------------

.proc fd_dup
    pha                         ; preserve oldfd across LOCK_ACQUIRE

    LOCK_ACQUIRE fd_lock

    pla                         ; A = oldfd

    ; Resolve old fd -> open object.
    jsr fd_lookup
    bcc @old_ok

    LOCK_RELEASE fd_lock

    sec
    rts

@old_ok:
    ; X = old open object.
    phx                         ; stack: old object

    ; Copy flags from old fd.
    jsr fd_get_flags_current
    sta fd_flags_tmp

    ; Find lowest free fd.
    jsr fd_find_free_current
    bcc @slot_ok

    plx                         ; discard old object

    LOCK_RELEASE fd_lock

    sec
    rts

@slot_ok:
    ; Y = new fd.
    ;
    ; Preserve new fd on stack. Do not use fd_pid_tmp:
    ; fd_attach overwrites it.
    phy                         ; stack: old object, new fd

    ; Restore old object into A.
    ply                         ; Y = new fd
    plx                         ; X = old object

    txa                         ; A = old object
    ldx current_pid             ; X = PID

    ; Preserve new fd for return.
    phy                         ; stack: new fd

    ; Attach:
    ;   X = current_pid
    ;   Y = new fd
    ;   A = old object
    jsr fd_attach

    ; Recover new fd return value.
    ply                         ; Y = new fd

    LOCK_RELEASE fd_lock

    tya                         ; A = new fd
    ldx #0
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_dup2
;
; Input:
;   A = old fd
;   Y = new fd
;
; Output:
;   C clear = success, A = new fd, X = 0
;   C set   = failure, Y = errno
; ------------------------------------------------------------

; ------------------------------------------------------------
; fd_dup2
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
;
; Notes:
;   - Validates newfd before taking fd_lock.
;   - Validates oldfd before closing/replacing newfd.
;   - dup2(oldfd, oldfd) returns oldfd without changing refcounts.
;   - fd_close_current is used because fd_lock is already held.
; ------------------------------------------------------------

.proc fd_dup2
    cpy #MAX_FDS
    bcc @newfd_ok

    ldy #EBADF
    sec
    rts

@newfd_ok:
    pha                         ; preserve oldfd
    phy                         ; preserve newfd

    LOCK_ACQUIRE fd_lock

    ply                         ; Y = newfd
    pla                         ; A = oldfd

    ; Preserve newfd across fd_lookup.
    ; fd_lookup returns errno in Y on failure, so this saved byte
    ; must be discarded with PLA, not PLY, on the failure path.
    phy

    ; Resolve old fd -> open object.
    jsr fd_lookup
    bcc @old_ok

    pla                         ; discard saved newfd
                                ; preserve Y = errno from fd_lookup

    LOCK_RELEASE fd_lock

    sec
    rts

@old_ok:
    ; X = old object
    ; fd_index_tmp = old fd
    ; stack top = saved newfd

    ply                         ; Y = newfd

    ; dup2(fd, fd) succeeds and changes nothing.
    cpy fd_index_tmp
    bne @different

    LOCK_RELEASE fd_lock

    tya
    ldx #0
    clc
    rts

@different:
    ; Preserve old object and newfd.
    phx                         ; old object
    phy                         ; newfd

    ; Copy descriptor flags from old fd.
    ; fd_index_tmp still contains old fd here.
    jsr fd_get_flags_current
    sta fd_flags_tmp

    ; Close target newfd if it is open.
    ; EBADF from closing target means it was already closed, which is OK.
    ply                         ; Y = newfd
    phy                         ; keep newfd for attach/return

    tya                         ; A = newfd
    jsr fd_close_current
    bcc @target_closed_ok

    cpy #EBADF
    beq @target_closed_ok

    ; Real close failure.
    ply                         ; discard newfd
    plx                         ; discard old object

    LOCK_RELEASE fd_lock

    sec
    rts

@target_closed_ok:
    ply                         ; Y = newfd
    plx                         ; X = old object

    ; Attach newfd to the old object.
    txa                         ; A = old object
    ldx current_pid             ; X = PID

    phy                         ; preserve newfd across fd_attach

    jsr fd_attach

    ply                         ; Y = newfd

    LOCK_RELEASE fd_lock

    tya                         ; A = newfd
    ldx #0
    clc
    rts
.endproc

