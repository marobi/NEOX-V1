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
.export ksys_get_launch_args2
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
.import proc_parent_pid
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_signal_pending
.import proc_exit_code
.import proc_launch_id
.import proc_launch_argc
.import proc_launch_arg0_len
.import proc_launch_arg1_len
.import proc_launch_arg0
.import proc_launch_arg1
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

spawn_argc:
    .res 1

spawn_arg0_ptrL:
    .res 1

spawn_arg0_ptrH:
    .res 1

spawn_arg1_ptrL:
    .res 1

spawn_arg1_ptrH:
    .res 1

spawn_arg0_len:
    .res 1

spawn_arg1_len:
    .res 1

spawn_copy_len:
    .res 1

spawn_stdin_fd:
    .res 1

spawn_stdout_fd:
    .res 1

spawn_stderr_fd:
    .res 1

spawn_errno:
    .res 1

spawn_fd_clone_args:
    .tag fd_clone_args

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Shared launch-slot pointer helper.
;
; Input:
;   X = PID
;   Y = slot selector:
;         0 = arg0
;         1 = arg1
;
; Output:
;   dev_ptr = selected launch slot
;
; Layout:
;   proc_launch_arg0 and proc_launch_arg1 are consecutive tables.
;   The combined slot index is:
;
;       PID + (slot * MAX_PROCS)
;
;   The byte offset is then calculated with mul8u using the configured
;   SPAWN_ARG_MAX value.
; ------------------------------------------------------------

SPAWN_SLOT_ARG0 = 0
SPAWN_SLOT_ARG1 = 1

.assert MAX_PROCS <= 128, error, "combined launch-slot index exceeds 8 bits"

.proc spawn_set_launch_dev_ptr
    txa
    cpy #SPAWN_SLOT_ARG0
    beq @index_ready

    clc
    adc #MAX_PROCS

@index_ready:
    ldx #SPAWN_ARG_MAX
    jsr mul8u

    clc
    adc #<proc_launch_arg0
    sta dev_ptr

    txa
    adc #>proc_launch_arg0
    sta dev_ptr+1
    rts
.endproc


; ------------------------------------------------------------
; spawn_copy_parent_to_launch_slot
;
; Input:
;   io_ptr   -> source bytes in active parent context
;   dev_ptr  -> shared destination launch slot
;   spawn_copy_len = byte count excluding NUL
;
; Return:
;   C clear = copied with NUL terminator
; ------------------------------------------------------------
.proc spawn_copy_parent_to_launch_slot
    ldy #0
    lda spawn_copy_len
    beq @zero
@loop:
    lda (io_ptr),y
    sta (dev_ptr),y
    iny
    cpy spawn_copy_len
    bne @loop
@zero:
    lda #0
    sta (dev_ptr),y
    clc
    rts
.endproc

; ------------------------------------------------------------
; spawn_copy_launch_slot_to_child
;
; Input:
;   dev_ptr  -> shared source launch slot
;   io_ptr   -> destination buffer in active child context
;   spawn_copy_len = byte count excluding NUL
;
; Return:
;   C clear = copied with NUL terminator
; ------------------------------------------------------------
.proc spawn_copy_launch_slot_to_child
    ldy #0
    lda spawn_copy_len
    beq @zero
@loop:
    lda (dev_ptr),y
    sta (io_ptr),y
    iny
    cpy spawn_copy_len
    bne @loop
@zero:
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
;   One transaction using PROC -> FILE_IO. Shared spawn scratch is not
;   touched until proc_gate is owned. Any pre-publication failure uses
;   one rollback path.
; ------------------------------------------------------------
.proc ksys_spawn_resident
    stx sched_ptr
    sty sched_ptr+1

    jsr proc_gate_acquire
    bcs @proc_locked

    ldy #EAGAIN
    sec
    rts

@proc_locked:
    ; Preserve caller argument pointer only after shared spawn state is locked.
    lda sched_ptr
    sta spawn_arg_ptrL
    lda sched_ptr+1
    sta spawn_arg_ptrH

    ldy #spawn_resident_args::entry
    lda (sched_ptr),y
    sta spawn_entryL
    iny
    lda (sched_ptr),y
    sta spawn_entryH

    ldy #spawn_resident_args::launch_id
    lda (sched_ptr),y
    sta spawn_launch_id_arg

    ldy #spawn_resident_args::argc
    lda (sched_ptr),y
    sta spawn_argc
    cmp #3
    bcc :+
    ldy #EINVAL
    jmp @fail_proc
:
    ldy #spawn_resident_args::arg0_ptr
    lda (sched_ptr),y
    sta spawn_arg0_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg0_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg0_len
    cmp #SPAWN_ARG_MAX
    bcc :+
    ldy #EINVAL
    jmp @fail_proc
:
    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg1_len
    cmp #SPAWN_ARG_MAX
    bcc :+
    ldy #EINVAL
    jmp @fail_proc
:
    iny
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
    beq :+
    ldy #EINVAL
    jmp @fail_proc
:
    ; Allocate the unpublished child while proc_gate remains owned.
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

    jsr proc_clear_launch_state
    lda spawn_launch_id_arg
    sta proc_launch_id,x
    lda spawn_argc
    sta proc_launch_argc,x

    lda spawn_argc
    beq @launch_ready

    lda spawn_arg0_len
    sta proc_launch_arg0_len,x
    sta spawn_copy_len
    lda spawn_arg0_ptrL
    sta io_ptr
    lda spawn_arg0_ptrH
    sta io_ptr+1
    ldy #SPAWN_SLOT_ARG0
    jsr spawn_set_launch_dev_ptr
    jsr spawn_copy_parent_to_launch_slot

    lda spawn_argc
    cmp #2
    bne @launch_ready

    ldx spawn_child_pid
    lda spawn_arg1_len
    sta proc_launch_arg1_len,x
    sta spawn_copy_len
    lda spawn_arg1_ptrL
    sta io_ptr
    lda spawn_arg1_ptrH
    sta io_ptr+1
    ldy #SPAWN_SLOT_ARG1
    jsr spawn_set_launch_dev_ptr
    jsr spawn_copy_parent_to_launch_slot

@launch_ready:
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
    ; Clone RP-owned cwd before publishing the child.
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
; ksys_get_launch_args2
;
; Input:
;   X/Y -> spawn_get_args2_args
;
; Purpose:
;   Copy the active child process launch arguments into caller-provided
;   context-local buffers.
; ------------------------------------------------------------
.proc ksys_get_launch_args2
    stx sched_ptr
    sty sched_ptr+1

    jsr proc_gate_acquire
    bcs @proc_locked
    ldy #EAGAIN
    sec
    rts

@proc_locked:
    lda sched_ptr
    sta spawn_arg_ptrL
    lda sched_ptr+1
    sta spawn_arg_ptrH

    ldx active_pid
    cpx #MAX_PROCS
    bcc :+
    ldy #EINVAL
    jmp spawn_release_proc_error
:
    ldy #spawn_get_args2_args::arg0_ptr
    lda (sched_ptr),y
    sta spawn_arg0_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg0_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg0_len
    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg1_len

    lda proc_launch_arg0_len,x
    cmp spawn_arg0_len
    bcc :+
    ldy #EINVAL
    jmp spawn_release_proc_error
:
    lda proc_launch_arg1_len,x
    cmp spawn_arg1_len
    bcc :+
    ldy #EINVAL
    jmp spawn_release_proc_error
:
    lda proc_launch_arg0_len,x
    sta spawn_copy_len
    lda spawn_arg0_ptrL
    sta io_ptr
    lda spawn_arg0_ptrH
    sta io_ptr+1
    ldy #SPAWN_SLOT_ARG0
    jsr spawn_set_launch_dev_ptr
    jsr spawn_copy_launch_slot_to_child

    ldx active_pid
    lda proc_launch_arg1_len,x
    sta spawn_copy_len
    lda spawn_arg1_ptrL
    sta io_ptr
    lda spawn_arg1_ptrH
    sta io_ptr+1
    ldy #SPAWN_SLOT_ARG1
    jsr spawn_set_launch_dev_ptr
    jsr spawn_copy_launch_slot_to_child

    lda spawn_arg_ptrL
    sta sched_ptr
    lda spawn_arg_ptrH
    sta sched_ptr+1

    ldx active_pid
    ldy #spawn_get_args2_args::argc_out
    lda proc_launch_argc,x
    sta (sched_ptr),y
    iny
    lda proc_launch_arg0_len,x
    sta (sched_ptr),y
    iny
    lda proc_launch_arg1_len,x
    sta (sched_ptr),y

    jmp spawn_release_proc_success
.endproc
