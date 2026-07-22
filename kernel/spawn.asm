; ============================================================
; spawn.asm
; NEOX - unified resident-image spawn
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"
.include "spawn.inc"
.include "fd.inc"
.include "mailbox.inc"

.export ksys_get_launch_id
.export ksys_get_launch_line
.export ksys_spawn_resident


.import proc_gate_acquire
.import proc_gate_release
.import file_io_gate_acquire
.import file_io_gate_release
.import rp_fs_exec
.import mul8u

.import proc_alloc_preloaded_unpublished
.import proc_set_state
.import proc_clear_launch_state
.import ctx_free_for_pid

.import fd_clone_between
.import fd_close_process

.import active_pid
.import console_owner_pid
.import scheduler_wake_console_owner
.import proc_parent_pid
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_signal_pending
.import proc_exit_code
.import proc_launch_id
.import proc_launch_line_len
.import proc_launch_line
.import wait_reason
.import wait_object


.importzp sched_ptr
.importzp io_ptr
.importzp dev_ptr

.segment "BSS"

spawn_arg_ptrL:
    .res 1

spawn_arg_ptrH:
    .res 1

spawn_entryL:
    .res 1

spawn_entryH:
    .res 1

spawn_child_pid:
    .res 1

spawn_launch_id_arg:
    .res 1

spawn_line_ptrL:
    .res 1

spawn_line_ptrH:
    .res 1

spawn_line_len:
    .res 1

spawn_copy_len:
    .res 1

spawn_stdin_fd:
    .res 1

spawn_stdout_fd:
    .res 1

spawn_stderr_fd:
    .res 1

spawn_flags:
    .res 1

spawn_errno:
    .res 1

spawn_fd_clone_args:
    .tag fd_clone_args

.segment "KERN_TEXT"

; ------------------------------------------------------------
; spawn_set_launch_line_dev_ptr
;
; Input:
;   X = PID
;
; Output:
;   dev_ptr = selected process launch-line slot
; ------------------------------------------------------------
.proc spawn_set_launch_line_dev_ptr
    txa
    ldx #SPAWN_LINE_MAX
    jsr mul8u

    clc
    adc #<proc_launch_line
    sta dev_ptr

    txa
    adc #>proc_launch_line
    sta dev_ptr+1
    rts
.endproc

; ------------------------------------------------------------
; spawn_copy_parent_to_launch_line
;
; Input:
;   io_ptr         -> source bytes in active parent context
;   dev_ptr        -> shared destination launch-line slot
;   spawn_line_len = byte count excluding NUL
; ------------------------------------------------------------
.proc spawn_copy_parent_to_launch_line
    ldy #0
@loop:
    cpy spawn_line_len
    beq @terminate
    lda (io_ptr),y
    sta (dev_ptr),y
    iny
    bra @loop

@terminate:
    lda #0
    sta (dev_ptr),y
    clc
    rts
.endproc

; ------------------------------------------------------------
; spawn_copy_launch_line_to_child
;
; Input:
;   dev_ptr        -> shared source launch-line slot
;   io_ptr         -> destination buffer in active child context
;   spawn_line_len = byte count excluding NUL
; ------------------------------------------------------------
.proc spawn_copy_launch_line_to_child
    ldy #0
@loop:
    cpy spawn_line_len
    beq @terminate
    lda (dev_ptr),y
    sta (io_ptr),y
    iny
    bra @loop

@terminate:
    lda #0
    sta (io_ptr),y
    clc
    rts
.endproc

; ------------------------------------------------------------
; spawn_clone_mapped_fd_locked
;
; Input:
;   A = fd number to clone from active parent into same child fd.
;   spawn_child_pid = pending child PID.
; ------------------------------------------------------------
.proc spawn_clone_mapped_fd_locked
    cmp #SPAWN_FD_CLOSED
    beq @closed

    sta spawn_fd_clone_args + fd_clone_args::source_fd
    sty spawn_fd_clone_args + fd_clone_args::target_fd

    lda active_pid
    sta spawn_fd_clone_args + fd_clone_args::source_pid

    lda spawn_child_pid
    sta spawn_fd_clone_args + fd_clone_args::target_pid

    ldx #<spawn_fd_clone_args
    ldy #>spawn_fd_clone_args
    jmp fd_clone_between

@closed:
    clc
    rts
.endproc

; spawn_validate_mapped_fd
;
; Input:
;   A = parent fd or SPAWN_FD_CLOSED
;
; Return:
;   C clear = accepted
;   C set   = invalid, Y = EBADF
; ------------------------------------------------------------
.proc spawn_validate_mapped_fd
    cmp #SPAWN_FD_CLOSED
    beq @ok
    cmp #MAX_FDS
    bcc @ok

    ldy #EBADF
    sec
    rts

@ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; spawn_clear_process_slot_locked
;
; Requires proc_gate. The setup child must not be runnable.
; Uses spawn_child_pid.
; ------------------------------------------------------------
.proc spawn_clear_process_slot_locked
    ldx spawn_child_pid
    jsr ctx_free_for_pid

    ldx spawn_child_pid
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x
    stz proc_signal_pending,x
    lda #EXIT_OK
    sta proc_exit_code,x

    lda #$FF
    sta proc_parent_pid,x
    sta proc_context,x

    stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x
    jsr proc_clear_launch_state

    lda #PROC_EMPTY
    jsr proc_set_state
    clc
    rts
.endproc

; ------------------------------------------------------------
; spawn_rollback_child_locked
;
; Requires lock order PROC -> FILE_IO with both gates held.
; Uses spawn_child_pid.
; ------------------------------------------------------------
.proc spawn_rollback_child_locked
    ldx spawn_child_pid
    jsr fd_close_process

    ; Continue clearing the unpublished process slot even though the
    ; configured resident-spawn descriptors are expected to close cleanly.
    jmp spawn_clear_process_slot_locked
.endproc

; ------------------------------------------------------------
; Common gate-release tails.

.proc spawn_release_proc_success
    jsr proc_gate_release
    bcs @ok

    ldy #EAGAIN
    sec
    rts

@ok:
    clc
    rts
.endproc

.proc spawn_release_proc_error
    sty spawn_errno
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts
.endproc

.proc spawn_release_both_success
    stz spawn_errno
    jsr file_io_gate_release
    bcs :+
    lda #EAGAIN
    sta spawn_errno
:
    jsr proc_gate_release
    bcs :+
    lda #EAGAIN
    sta spawn_errno
:
    lda spawn_errno
    beq @ok
    tay
    sec
    rts
@ok:
    clc
    rts
.endproc

.proc spawn_release_both_error
    sty spawn_errno
    jsr file_io_gate_release
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts
.endproc

; ksys_spawn_resident
;
; Input:
;   X/Y -> spawn_resident_args
;
; Return:
;   C clear = child published, A = child PID
;   C set   = failure, Y = errno
;
; Locking:
;   One transaction using PROC -> FILE_IO. The caller argument pointer
;   remains on the current process stack while proc_gate_acquire may
;   block/yield. Shared spawn scratch is not touched until proc_gate is
;   owned. Any pre-publication failure uses one rollback path.
; ------------------------------------------------------------
.proc ksys_spawn_resident
    ; proc_gate_acquire may block/yield. Preserve the process-private
    ; syscall argument pointer on the current process hardware stack.
    txa
    pha
    tya
    pha

    jsr proc_gate_acquire
    bcs @proc_locked

    pla
    pla
    ldy #EAGAIN
    sec
    rts

@proc_locked:
    pla
    sta spawn_arg_ptrH
    sta sched_ptr+1
    pla
    sta spawn_arg_ptrL
    sta sched_ptr

    ldy #spawn_resident_args::entry
    lda (sched_ptr),y
    sta spawn_entryL
    iny
    lda (sched_ptr),y
    sta spawn_entryH

    ldy #spawn_resident_args::launch_id
    lda (sched_ptr),y
    sta spawn_launch_id_arg

    ldy #spawn_resident_args::arg_line_ptr
    lda (sched_ptr),y
    sta spawn_line_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_line_ptrH

    ldy #spawn_resident_args::arg_line_len
    lda (sched_ptr),y
    sta spawn_line_len
    cmp #SPAWN_LINE_MAX
    bcc :+
    ldy #EINVAL
    jmp @fail_proc
:
    ldy #spawn_resident_args::stdin_fd
    lda (sched_ptr),y
    sta spawn_stdin_fd
    jsr spawn_validate_mapped_fd
    bcc :+
    jmp @fail_proc
:
    ldy #spawn_resident_args::stdout_fd
    lda (sched_ptr),y
    sta spawn_stdout_fd
    jsr spawn_validate_mapped_fd
    bcc :+
    jmp @fail_proc
:
    ldy #spawn_resident_args::stderr_fd
    lda (sched_ptr),y
    sta spawn_stderr_fd
    jsr spawn_validate_mapped_fd
    bcc :+
    jmp @fail_proc
:
    ldy #spawn_resident_args::flags
    lda (sched_ptr),y
    sta spawn_flags
    and #($FF ^ SPAWN_FLAGS_VALID)
    beq :+
    ldy #EINVAL
    jmp @fail_proc
:
    lda active_pid
    ldx spawn_entryL
    ldy spawn_entryH
    jsr proc_alloc_preloaded_unpublished
    bcc @allocated

    ldy #ENOMEM
    jmp @fail_proc

@allocated:
    sta spawn_child_pid
    tax

    ; The existing spawn flags byte is the child's explicit initial
    ; proc_flags value. There is no implicit inheritance from the parent.
    lda spawn_flags
    sta proc_flags,x

    jsr proc_clear_launch_state
    lda spawn_launch_id_arg
    sta proc_launch_id,x
    lda spawn_line_len
    sta proc_launch_line_len,x

    lda spawn_line_ptrL
    sta io_ptr
    lda spawn_line_ptrH
    sta io_ptr+1
    ldx spawn_child_pid
    jsr spawn_set_launch_line_dev_ptr
    jsr spawn_copy_parent_to_launch_line

    jsr file_io_gate_acquire
    bcs @file_locked

    ldy #EAGAIN
    sty spawn_errno
    jsr spawn_clear_process_slot_locked
    ldy spawn_errno
    jmp spawn_release_proc_error

@file_locked:
    lda spawn_stdin_fd
    ldy #STDIN
    jsr spawn_clone_mapped_fd_locked
    bcc :+
    jmp @rollback
:
    lda spawn_stdout_fd
    ldy #STDOUT
    jsr spawn_clone_mapped_fd_locked
    bcc :+
    jmp @rollback
:
    lda spawn_stderr_fd
    ldy #STDERR
    jsr spawn_clone_mapped_fd_locked
    bcc :+
    jmp @rollback
:
    stz io_ptr
    stz io_ptr+1
    lda #RP_FS_OP_CWD_CLONE
    ldx spawn_child_pid
    ldy active_pid
    jsr rp_fs_exec
    bcc @publish

@rollback:
    sty spawn_errno
    jsr spawn_rollback_child_locked
    ldy spawn_errno
    jmp spawn_release_both_error

@publish:
    ldx spawn_child_pid
    lda #PROC_NEW
    jsr proc_set_state

    ; A synchronous foreground spawn transfers console ownership only when
    ; the spawning parent currently owns that routed console.
    lda spawn_flags
    and #PROC_FLAG_FOREGROUND
    beq :+

    lda console_owner_pid
    cmp active_pid
    bne :+

    lda spawn_child_pid
    sta console_owner_pid
    jsr scheduler_wake_console_owner
:
    lda spawn_arg_ptrL
    sta sched_ptr
    lda spawn_arg_ptrH
    sta sched_ptr+1

    ldy #spawn_resident_args::result_pid
    lda spawn_child_pid
    sta (sched_ptr),y

    jsr spawn_release_both_success
    bcc @success
    rts

@success:
    lda spawn_child_pid
    clc
    rts

@fail_proc:
    jmp spawn_release_proc_error
.endproc

; ------------------------------------------------------------
; ksys_get_launch_id
;
; Input:
;   none
;
; Return:
;   C clear = success, A = launch selector for active_pid
;   C set   = failure, Y = errno
;
; Purpose:
;   Let a committed resident child retrieve the launch selector that
;   its parent assigned before the child was published as PROC_NEW.
; ------------------------------------------------------------

.proc ksys_get_launch_id
    ldx active_pid
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    lda proc_launch_id,x
    cmp #SPAWN_LAUNCH_NONE
    bne @ok

    ldy #EINVAL
    sec
    rts

@ok:
    clc
    rts
.endproc


; ------------------------------------------------------------
; ksys_get_launch_line
;
; Input:
;   X/Y -> spawn_get_line_args in the active child context
;
; Return:
;   C clear = copied and NUL-terminated
;   C set   = failure, Y = errno
;
; The launch line remains opaque to the kernel.
; ------------------------------------------------------------
.proc ksys_get_launch_line
    txa
    pha
    tya
    pha

    jsr proc_gate_acquire
    bcs @proc_locked

    pla
    pla
    ldy #EAGAIN
    sec
    rts

@proc_locked:
    pla
    sta spawn_arg_ptrH
    sta sched_ptr+1
    pla
    sta spawn_arg_ptrL
    sta sched_ptr

    ldx active_pid
    cpx #MAX_PROCS
    bcc :+
    ldy #EINVAL
    jmp spawn_release_proc_error
:
    ldy #spawn_get_line_args::buffer_ptr
    lda (sched_ptr),y
    sta spawn_line_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_line_ptrH

    ldy #spawn_get_line_args::buffer_size
    lda (sched_ptr),y
    beq @invalid
    sta spawn_copy_len

    ldx active_pid
    lda proc_launch_line_len,x
    cmp spawn_copy_len
    bcc @size_ok

@invalid:
    ldy #EINVAL
    jmp spawn_release_proc_error

@size_ok:
    sta spawn_line_len
    lda spawn_line_ptrL
    sta io_ptr
    lda spawn_line_ptrH
    sta io_ptr+1

    ldx active_pid
    jsr spawn_set_launch_line_dev_ptr
    jsr spawn_copy_launch_line_to_child

    lda spawn_arg_ptrL
    sta sched_ptr
    lda spawn_arg_ptrH
    sta sched_ptr+1

    ldy #spawn_get_line_args::result_len
    lda spawn_line_len
    sta (sched_ptr),y

    jmp spawn_release_proc_success
.endproc
