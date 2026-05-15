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
.include "math8.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"

.export fd_init_tables
.export fd_init_process
.export fd_close_process
.export fd_read
.export fd_write
.export fd_close
.export fd_dup
.export fd_dup2
;---------------------------------------------------
.import current_pid

.import proc_fd_obj
.import proc_fd_flags

.import open_type
.import open_refcnt
.import open_flags
.import open_dev

.import dev_resolve_op
.import dev_call

.importzp fd_ptr
.importzp fd_flags_tmp
.importzp fd_obj_tmp
.importzp fd_index_tmp
.importzp fd_pid_tmp

.segment "KERN_TEXT"

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
; fd_init_tables
;
; Purpose:
;   Initialize global open-object table.
;
; Behavior:
;   - clears all open-object slots
;   - installs three console objects:
;       0 = stdin
;       1 = stdout
;       2 = stderr
;
; Notes:
;   Refcounts start at 0 and are incremented when processes
;   attach descriptors.
; ------------------------------------------------------------

.proc fd_init_tables
    ldx #$00

@clear:
    stz open_type,x
    stz open_refcnt,x
    stz open_flags,x
    stz open_dev,x

    inx
    cpx #OPEN_MAX
    bne @clear

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
; fd_close
;
; Purpose:
;   Close one file descriptor belonging to current_pid.
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
;
; Behavior:
;   - validates fd
;   - clears proc_fd_obj[current_pid][fd]
;   - clears proc_fd_flags[current_pid][fd]
;   - decrements open object refcount
;   - if refcount reaches zero and object is a device:
;       calls DEVOP_CLOSE
;
; Notes:
;   - FD table/refcount mutation is non-preemptible.
;   - The open object and fd index are kept on the process stack.
;   - Device close is called after leaving the critical section.
;   - Do not use fd_pid_tmp/fd_index_tmp/fd_obj_tmp as live
;     storage across JSR boundaries.
; ------------------------------------------------------------

.proc fd_close
    php
    sei

    ; Resolve fd -> open object.
    ; fd_lookup returns:
    ;   C clear
    ;   X = open object
    ;   fd_index_tmp = fd index
    jsr fd_lookup
    bcc @fd_ok

    plp
    sec
    rts

@fd_ok:
    ; Preserve:
    ;   X = open object
    ;   fd_index_tmp = fd index
    phx

    ldy fd_index_tmp
    phy

    ; --------------------------------------------------------
    ; Calculate:
    ;
    ;   offset = current_pid * MAX_FDS
    ; --------------------------------------------------------

    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; Restore fd index into Y.
    ply

    ; --------------------------------------------------------
    ; Clear proc_fd_obj[current_pid][fd].
    ; --------------------------------------------------------

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    lda #FD_NONE
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; Clear proc_fd_flags[current_pid][fd].
    ; --------------------------------------------------------

    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    lda #0
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; Decrement open object refcount.
    ; --------------------------------------------------------

    plx                         ; X = open object

    lda open_refcnt,x
    beq @done_ok_locked

    dec open_refcnt,x
    lda open_refcnt,x
    bne @done_ok_locked

    ; --------------------------------------------------------
    ; Last reference closed.
    ;
    ; For now only device close is supported.
    ; Device close is called after leaving the critical section.
    ; X still contains the open object index.
    ; --------------------------------------------------------

    lda open_type,x
    cmp #OBJ_DEVICE
    beq @close_device

@done_ok_locked:
    plp

@done_ok:
    lda #0
    tax
    clc
    rts

@close_device:
    ; Leave critical section before backend close.
    ; Current console close is non-blocking, but this is the
    ; safer model for later devices/files.
    plp

    lda #DEVOP_CLOSE
    jsr dev_resolve_op
    bcs @done_ok

    jsr dev_call
    bcs @fail

    lda #0
    tax
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; fd_init_process
;
; Purpose:
;   Initialize fd table for a new process.
;
; Input:
;   X = pid
;
; Behavior:
;   - clears fd table
;   - attaches:
;       fd 0 → stdin (READ)
;       fd 1 → stdout (WRITE)
;       fd 2 → stderr (WRITE)
;
; Notes:
;   Uses fd_attach to ensure consistent refcounting.
; ------------------------------------------------------------

.proc fd_init_process
    ; --------------------------------------------------------
    ; Clear proc_fd_obj[pid][*]
    ; --------------------------------------------------------
    lda #<proc_fd_obj
    sta fd_ptr
    lda #>proc_fd_obj
    sta fd_ptr+1

    txa
    beq @obj_base_done
    tay

@obj_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @obj_base_loop

@obj_base_done:
    ldy #0
    lda #FD_NONE

@clear_obj:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_obj

    ; --------------------------------------------------------
    ; Clear proc_fd_flags[pid][*]
    ; --------------------------------------------------------
    lda #<proc_fd_flags
    sta fd_ptr
    lda #>proc_fd_flags
    sta fd_ptr+1

    txa
    beq @flags_base_done
    tay

@flags_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @flags_base_loop

@flags_base_done:
    ldy #0
    lda #0

@clear_flags:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_flags

    ; --------------------------------------------------------
    ; Attach standard descriptors
    ; --------------------------------------------------------

    ; fd 0 → stdin (READ)
    lda #FD_FLAG_READ
    sta fd_flags_tmp
    ldy #STDIN
    lda #STDIN
    jsr fd_attach

    ; fd 1 → stdout (WRITE)
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDOUT
    lda #STDOUT
    jsr fd_attach

    ; fd 2 → stderr (WRITE)
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDERR
    lda #STDERR
    jsr fd_attach

    rts
.endproc

; ------------------------------------------------------------
; fd_close_process
;
; Purpose:
;   Close all file descriptors owned by one process.
;
; Input:
;   X = PID
;
; Output:
;   C clear = success
;
;   C set   = failure
;             Y = errno
;
; Behavior:
;   For each fd in proc_fd_obj[PID]:
;     - if fd is open:
;         clear proc_fd_obj[PID][fd]
;         clear proc_fd_flags[PID][fd]
;         decrement open_refcnt[object]
;         if refcount becomes zero and object is a device:
;             call DEVOP_CLOSE
;
; Notes:
;   - This closes descriptors for the PID passed in X, not current_pid.
;   - FD table/refcount mutation is protected with php/sei/plp.
;   - Device close calls are made after leaving the critical section.
;   - This routine uses the stack to remember PID/fd/object across
;     subroutine calls instead of using shared tmp-vars as live storage.
; ------------------------------------------------------------

.proc fd_close_process
    ; Save target PID.
    phx

    ; Validate PID.
    cpx #MAX_PROCS
    bcc @pid_ok

    plx
    ldy #EINVAL
    sec
    rts

@pid_ok:
    ; fd index = 0
    ldy #0

@loop:
    cpy #MAX_FDS
    bne @check_fd

    ; Done.
    plx                     ; discard saved PID
    clc
    rts

@check_fd:
    ; Stack currently:
    ;   saved PID
    ;
    ; Save fd index while we calculate pointers.
    phy

    php
    sei

    ; Get target PID from stack without disturbing it:
    ; stack top = saved fd index
    ; below     = saved PID
    ;
    ; Pull temporarily, then restore.
    ply                     ; Y = fd index
    plx                     ; X = PID
    phx                     ; restore saved PID
    phy                     ; restore fd index

    ; offset = PID * MAX_FDS
    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; Build proc_fd_obj[PID] pointer.
    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ; Restore fd index for table access.
    ply                     ; Y = fd index

    lda (fd_ptr),y
    cmp #FD_NONE
    bne @is_open

    ; Closed fd; nothing to do.
    plp

    iny
    bra @loop

@is_open:
    ; A = open object.
    ; Save fd index and open object on stack.
    pha                     ; open object
    phy                     ; fd index

    ; Clear proc_fd_obj[PID][fd].
    lda #FD_NONE
    sta (fd_ptr),y

    ; Build proc_fd_flags[PID] pointer.
    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ; Restore fd index for flag clear, then save again.
    ply                     ; Y = fd index
    phy

    lda #0
    sta (fd_ptr),y

    ; Restore object into X.
    ply                     ; Y = fd index
    pla                     ; A = open object
    tax

    ; Save next fd index on stack before possible device close path.
    iny
    phy                     ; next fd index

    ; Decrement refcount.
    lda open_refcnt,x
    beq @finish_locked

    dec open_refcnt,x
    lda open_refcnt,x
    bne @finish_locked

    ; Last reference: if device, close backend after leaving critical section.
    lda open_type,x
    cmp #OBJ_DEVICE
    beq @close_device

@finish_locked:
    plp

    ; Restore next fd index.
    ply
    bra @loop

@close_device:
    ; Need object index after leaving critical section.
    phx                     ; object
    plp

    ; Restore object for device dispatch.
    plx

    lda #DEVOP_CLOSE
    jsr dev_resolve_op
    bcs @after_device_close

    jsr dev_call
    bcs @device_close_fail

@after_device_close:
    ; Restore next fd index and continue.
    ply
    bra @loop

@device_close_fail:
    ; Drop next fd index before returning error.
    ply

    ; Drop saved PID.
    plx

    sec
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
;   Device backend returns directly to fd_read caller:
;
;   C clear = success
;             A/X = bytes read
;
;   C set   = failure
;             Y = errno
;
; Flow:
;   fd -> open object -> permission -> object type -> device op
;
; Notes:
;   - FD table lookup, permission check, object check, and device
;     vector resolution are protected.
;   - We do not call the device backend with JSR from inside this
;     routine. We tail-jump through dev_call_tail.
;   - Device routine RTS returns to fd_read's caller.
;   - Device backend may enable IRQ before blocking/yielding.
; ------------------------------------------------------------

.proc fd_read
    php
    sei

    ; Preserve requested length while resolving fd/device.
    pha
    phx

    ; Resolve fd -> open object.
    tya
    jsr fd_lookup
    bcc @fd_ok

    ; Drop saved length and restore caller interrupt state.
    plx
    pla
    plp
    sec
    rts

@fd_ok:
    ; Save open object across permission check.
    phx

    lda #FD_FLAG_READ
    jsr fd_check_perm
    bcc @perm_ok

    ; Drop saved object and saved length.
    plx
    plx
    pla
    plp
    sec
    rts

@perm_ok:
    ; Restore open object into X.
    plx

    ; For now only device objects are supported by fd_read.
    lda open_type,x
    cmp #OBJ_DEVICE
    beq @device_ok

    ; Drop saved length.
    plx
    pla
    plp
    ldy #ENODEV
    sec
    rts

@device_ok:
    ; Resolve device READ operation.
    lda #DEVOP_READ
    jsr dev_resolve_op
    bcc @op_ok

    ; Drop saved length.
    plx
    pla
    plp
    sec
    rts

@op_ok:
    ; Restore requested length for backend.
    plx
    pla

    ; Restore original interrupt state before entering device code.
    ;
    ; There is a small window between PLP and JMP. That is acceptable
    ; for now because dev_call_tail immediately jumps through dev_ptr.
    ; If this ever becomes a real race, move the vector to stack/local
    ; storage or require device backends to enter with IRQ disabled.
    plp

    jmp dev_call
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
;   Device backend returns directly to fd_write caller:
;
;   C clear = success
;             A/X = bytes written
;
;   C set   = failure
;             Y = errno
;
; Flow:
;   fd -> open object -> permission -> object type -> device op
;
; Notes:
;   - FD table lookup, permission check, object check, and device
;     vector resolution are protected.
;   - We do not call the device backend with JSR from inside this
;     routine. We tail-jump through dev_call_tail.
;   - Device routine RTS returns to fd_write's caller.
;   - Device backend may enable IRQ before blocking/yielding.
; ------------------------------------------------------------

.proc fd_write
    php
    sei

    ; Preserve requested length while resolving fd/device.
    pha
    phx

    ; Resolve fd -> open object.
    tya
    jsr fd_lookup
    bcc @fd_ok

    ; Drop saved length and restore caller interrupt state.
    plx
    pla
    plp
    sec
    rts

@fd_ok:
    ; Save open object across permission check.
    phx

    lda #FD_FLAG_WRITE
    jsr fd_check_perm
    bcc @perm_ok

    ; Drop saved object and saved length.
    plx
    plx
    pla
    plp
    sec
    rts

@perm_ok:
    ; Restore open object into X.
    plx

    ; For now only device objects are supported by fd_write.
    lda open_type,x
    cmp #OBJ_DEVICE
    beq @device_ok

    ; Drop saved length.
    plx
    pla
    plp
    ldy #ENODEV
    sec
    rts

@device_ok:
    ; Resolve device WRITE operation.
    lda #DEVOP_WRITE
    jsr dev_resolve_op
    bcc @op_ok

    ; Drop saved length.
    plx
    pla
    plp
    sec
    rts

@op_ok:
    ; Restore requested length for backend.
    plx
    pla

    ; Restore original interrupt state before entering device code.
    plp

    jmp dev_call
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
; fd_dup
;
; Purpose:
;   Duplicate one fd into the lowest free fd slot of current_pid.
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
;   - FD table manipulation is non-preemptible.
;   - The old open object is saved on the stack.
;   - The new fd is saved with PHY across fd_attach.
;   - Do not use fd_pid_tmp/fd_index_tmp as live storage across JSR.
; ------------------------------------------------------------

.proc fd_dup
    php
    sei

    ; Resolve old fd -> open object.
    jsr fd_lookup
    bcc @old_ok

    plp
    sec
    rts

@old_ok:
    ; Save old open object on stack.
    txa
    pha

    ; Copy old fd flags into fd_flags_tmp.
    jsr fd_get_flags_current
    sta fd_flags_tmp

    ; Find lowest free fd for current process.
    jsr fd_find_free_current
    bcc @slot_ok

    ; Drop saved old object.
    pla

    plp
    sec
    rts

@slot_ok:
    ; Y = new fd.
    ; A stack top = old open object.

    ; Restore old object into A.
    pla

    ; Save new fd across fd_attach.
    phy

    ; Attach new fd to same open object.
    ldx current_pid
    ; Y still contains new fd.
    ; A contains old open object.
    jsr fd_attach

    ; Restore new fd and return it in A.
    ply
    tya

    ldx #0

    plp
    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_dup2
;
; Purpose:
;   Duplicate oldfd into exactly newfd.
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
; Semantics:
;   if oldfd invalid:
;       fail EBADF
;
;   if newfd >= MAX_FDS:
;       fail EBADF
;
;   if oldfd == newfd:
;       return newfd
;
;   if newfd already open:
;       close(newfd)
;
;   newfd references the same open object as oldfd.
;   newfd receives the same per-fd flags as oldfd.
;
; Notes:
;   - Uses PHY/PLY/PHX/PLX instead of shared temp variables
;     for live values across subroutine calls.
;   - FD table mutation is made non-preemptible.
;   - fd_flags_tmp is only written immediately before fd_attach.
; ------------------------------------------------------------

.proc fd_dup2
    ; Validate newfd range before entering critical section.
    cpy #MAX_FDS
    bcc @newfd_ok

    ldy #EBADF
    sec
    rts

@newfd_ok:
    php
    sei

    ; Save requested newfd on stack.
    phy

    ; Resolve oldfd -> open object.
    jsr fd_lookup
    bcc @old_ok

    ; Drop saved newfd without clobbering Y errno.
    pla

    plp
    sec
    rts

@old_ok:
    ; fd_lookup:
    ;   X            = old open object
    ;   fd_index_tmp = old fd
    ;   stack top    = requested newfd

    ply                     ; Y = newfd

    ; dup2(oldfd, oldfd) returns oldfd unchanged.
    cpy fd_index_tmp
    bne @different

    tya
    ldx #0

    plp
    clc
    rts

@different:
    ; Save old open object and newfd while fetching old flags.
    phx                     ; old open object
    phy                     ; newfd

    ; fd_index_tmp still refers to oldfd here.
    jsr fd_get_flags_current

    ; Stack:
    ;   top:    newfd
    ;           old open object
    ;
    ; A = old fd flags
    pha                     ; old fd flags

    ; Restore into registers:
    ;   A = flags
    ;   X = old open object
    ;   Y = newfd
    pla                     ; A = flags
    ply                     ; Y = newfd
    plx                     ; X = old open object

    ; --------------------------------------------------------
    ; If newfd is already open, close it first.
    ;
    ; Preserve:
    ;   A = old flags
    ;   X = old object
    ;   Y = newfd
    ; --------------------------------------------------------

    pha                     ; old flags
    phx                     ; old object
    phy                     ; newfd

    tya
    jsr fd_lookup
    bcs @target_already_closed

    ; Target fd is open. Restore values, then close target fd.
    ply                     ; Y = newfd
    plx                     ; X = old object
    pla                     ; A = old flags

    ; Preserve values across fd_close.
    pha                     ; old flags
    phx                     ; old object
    phy                     ; newfd

    tya
    jsr fd_close
    bcc @target_closed_ok

    ; fd_close failed.
    ; Drop saved newfd/object/flags without clobbering Y errno.
    pla
    pla
    pla

    plp
    sec
    rts

@target_closed_ok:
    ply                     ; Y = newfd
    plx                     ; X = old object
    pla                     ; A = old flags
    bra @attach

@target_already_closed:
    ; fd_lookup failed for newfd, which is fine: target is closed.
    ; Restore saved values.
    ply                     ; Y = newfd
    plx                     ; X = old object
    pla                     ; A = old flags

@attach:
    ; A = old flags
    ; X = old open object
    ; Y = newfd

    ; fd_attach expects fd_flags_tmp to contain copied flags.
    sta fd_flags_tmp

    ; Move old object to A for fd_attach.
    txa

    ; Save newfd across fd_attach. Do not rely on Y survival.
    phy

    ldx current_pid
    ; Y = newfd
    ; A = old open object
    jsr fd_attach

    ; Return newfd in A.
    ply
    tya

    ldx #0

    plp
    clc
    rts
.endproc
