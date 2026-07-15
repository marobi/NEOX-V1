; ============================================================
; spawn.asm
; NEOX - parent-controlled resident spawn setup ABI
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"
.include "spawn.inc"
.include "fd.inc"
.include "mailbox.inc"

.export ksys_spawn_alloc_resident
.export ksys_spawn_fd_inherit
.export ksys_spawn_fd_dup_child
.export ksys_spawn_fd_close
.export ksys_spawn_commit
.export ksys_spawn_abort
.export ksys_spawn_set_launch_id
.export ksys_get_launch_id
.export ksys_spawn_set_args2
.export ksys_get_launch_args2

.export spawn_validate_setup_child

.import proc_gate_acquire
.import proc_gate_release
.import file_io_gate_acquire
.import file_io_gate_release
.import rp_fs_exec

.import proc_alloc_preloaded_setup
.import proc_set_state
.import ctx_free_for_pid

.import fd_clone_between
.import fd_close_pid
.import fd_close_process

.import active_pid
.import proc_state
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

spawn_flags:
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

spawn_arg0_max:
    .res 1

spawn_arg1_max:
    .res 1

spawn_offset_lo:
    .res 1

spawn_offset_hi:
    .res 1

spawn_copy_len:
    .res 1

spawn_child_args_internal:
    .tag spawn_child_args

spawn_parent_fd:
    .res 1

spawn_child_fd:
    .res 1

spawn_source_fd:
    .res 1

spawn_target_fd:
    .res 1

spawn_errno:
    .res 1

spawn_fd_clone_args:
    .tag fd_clone_args

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Shared launch slot pointer helpers.
; ------------------------------------------------------------
.proc spawn_set_arg0_dev_ptr
    ; offset = pid * SPAWN_ARG_MAX. Current SPAWN_ARG_MAX is 24:
    ; pid * 24 = (pid * 16) + (pid * 8).
    txa
    asl
    asl
    asl
    sta spawn_offset_lo
    txa
    asl
    asl
    asl
    asl
    clc
    adc spawn_offset_lo
    clc
    adc #<proc_launch_arg0
    sta dev_ptr
    lda #>proc_launch_arg0
    adc #0
    sta dev_ptr+1
    rts
.endproc

.proc spawn_set_arg1_dev_ptr
    ; offset = pid * SPAWN_ARG_MAX. Current SPAWN_ARG_MAX is 24:
    ; pid * 24 = (pid * 16) + (pid * 8).
    txa
    asl
    asl
    asl
    sta spawn_offset_lo
    txa
    asl
    asl
    asl
    asl
    clc
    adc spawn_offset_lo
    clc
    adc #<proc_launch_arg1
    sta dev_ptr
    lda #>proc_launch_arg1
    adc #0
    sta dev_ptr+1
    rts
.endproc


; ------------------------------------------------------------
; spawn_clear_launch_state_for_pid
;
; Input:
;   X = PID
; ------------------------------------------------------------
.proc spawn_clear_launch_state_for_pid
    lda #SPAWN_LAUNCH_NONE
    sta proc_launch_id,x
    stz proc_launch_argc,x
    stz proc_launch_arg0_len,x
    stz proc_launch_arg1_len,x
    rts
.endproc

; ------------------------------------------------------------
; spawn_clone_parent_cwd_to_child
;
; Input:
;   X = child PID
;
; Purpose:
;   Clone the active parent's shared cwd mirror into the child shared cwd
;   mirror. first_run_entry later copies the child mirror into the child
;   context-private cwd storage.
; ------------------------------------------------------------

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
; spawn_clone_one_default_fd
;
; Input:
;   A = fd number to clone from active parent into same child fd.
;   spawn_child_pid = pending child PID.
; ------------------------------------------------------------
.proc spawn_clone_one_default_fd
    sta spawn_fd_clone_args + fd_clone_args::source_fd
    sta spawn_fd_clone_args + fd_clone_args::target_fd

    lda active_pid
    sta spawn_fd_clone_args + fd_clone_args::source_pid

    lda spawn_child_pid
    sta spawn_fd_clone_args + fd_clone_args::target_pid

    ldx #<spawn_fd_clone_args
    ldy #>spawn_fd_clone_args
    jmp fd_clone_between
.endproc

; ------------------------------------------------------------
; spawn_clone_default_stdio
;
; Purpose:
;   Default child fd table setup:
;     child 0 <- parent 0
;     child 1 <- parent 1
;     child 2 <- parent 2
; ------------------------------------------------------------
.proc spawn_clone_default_stdio
    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda #STDIN
    jsr spawn_clone_one_default_fd
    bcs @fail_release

    lda #STDOUT
    jsr spawn_clone_one_default_fd
    bcs @fail_release

    lda #STDERR
    jsr spawn_clone_one_default_fd
    bcs @fail_release

    jsr file_io_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr file_io_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; spawn_abort_current_child_internal
;
; Purpose:
;   Abort spawn_child_pid through the public abort implementation.
; ------------------------------------------------------------
.proc spawn_abort_current_child_internal
    lda spawn_child_pid
    sta spawn_child_args_internal + spawn_child_args::child_pid
    ldx #<spawn_child_args_internal
    ldy #>spawn_child_args_internal
    jmp ksys_spawn_abort
.endproc

; ------------------------------------------------------------
; spawn_validate_setup_child
;
; Input:
;   A = child PID
;
; Return:
;   C clear = valid pending child owned by active_pid
;             X = child PID
;
;   C set   = failure
;             Y = errno
;
; Notes:
;   This validates the parent-controlled setup rule:
;     proc_state[child] == PROC_SETUP
;     proc_parent_pid[child] == active_pid
; ------------------------------------------------------------

.proc spawn_validate_setup_child
    cmp #MAX_PROCS
    bcc @pid_range_ok

    ldy #EINVAL
    sec
    rts

@pid_range_ok:
    tax
    cpx #IDLE_PID
    bne @not_idle

    ldy #EINVAL
    sec
    rts

@not_idle:
    lda proc_state,x
    cmp #PROC_SETUP
    beq @state_ok

    ldy #EINVAL
    sec
    rts

@state_ok:
    lda proc_parent_pid,x
    cmp active_pid
    beq @owner_ok

    ldy #EINVAL
    sec
    rts

@owner_ok:
    clc
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_alloc_resident
;
; Input:
;   X/Y -> spawn_alloc_resident_args
;
; Return:
;   C clear = success
;             A = child PID
;             result_pid written to arg block
;
;   C set   = failure
;             Y = errno
;
; Purpose:
;   Allocate a resident/preloaded child owned by active_pid.  The
;   child is left in PROC_SETUP and is not runnable until
;   ksys_spawn_commit is called by the same parent.
; ------------------------------------------------------------

.proc ksys_spawn_alloc_resident
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ; Copy caller arguments before proc_gate_acquire can block/yield.
    ldy #spawn_alloc_resident_args::entry
    lda (sched_ptr),y
    sta spawn_entryL

    iny
    lda (sched_ptr),y
    sta spawn_entryH

    ldy #spawn_alloc_resident_args::flags
    lda (sched_ptr),y
    sta spawn_flags
    beq @flags_ok

    ldy #EINVAL
    sec
    rts

@flags_ok:
    jsr proc_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda active_pid
    ldx spawn_entryL
    ldy spawn_entryH
    jsr proc_alloc_preloaded_setup
    bcc @allocated

    jsr proc_gate_release
    ldy #ENOMEM
    sec
    rts

@allocated:
    sta spawn_child_pid
    tax

    ; Initialize launch metadata and snapshot the parent's cwd before
    ; the child is allowed to run.
    jsr spawn_clear_launch_state_for_pid

    jsr proc_gate_release
    bcs @released_ok

    ldy #EAGAIN
    sec
    rts

@released_ok:
    ; Default child fd table setup: inherit stdin/stdout/stderr.
    jsr spawn_clone_default_stdio
    bcc @stdio_ok

    sty spawn_errno
    jsr spawn_abort_current_child_internal
    ldy spawn_errno
    sec
    rts

@stdio_ok:
    lda spawn_arg_ptrL
    sta sched_ptr
    lda spawn_arg_ptrH
    sta sched_ptr+1

    ldy #spawn_alloc_resident_args::result_pid
    lda spawn_child_pid
    sta (sched_ptr),y

    lda spawn_child_pid
    clc
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_fd_inherit
;
; Input:
;   X/Y -> spawn_fd_inherit_args
;
; Purpose:
;   Clone active parent fd parent_fd into child fd child_fd.
; ------------------------------------------------------------

.proc ksys_spawn_fd_inherit
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ; Copy caller arguments before file_io_gate_acquire can block/yield.
    ldy #spawn_fd_inherit_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ldy #spawn_fd_inherit_args::parent_fd
    lda (sched_ptr),y
    sta spawn_parent_fd

    ldy #spawn_fd_inherit_args::child_fd
    lda (sched_ptr),y
    sta spawn_child_fd

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    lda active_pid
    sta spawn_fd_clone_args + fd_clone_args::source_pid

    lda spawn_parent_fd
    sta spawn_fd_clone_args + fd_clone_args::source_fd

    lda spawn_child_pid
    sta spawn_fd_clone_args + fd_clone_args::target_pid

    lda spawn_child_fd
    sta spawn_fd_clone_args + fd_clone_args::target_fd

    ldx #<spawn_fd_clone_args
    ldy #>spawn_fd_clone_args
    jsr fd_clone_between
    bcs @fail_release

    jsr file_io_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr file_io_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_fd_dup_child
;
; Input:
;   X/Y -> spawn_fd_dup_child_args
;
; Purpose:
;   Duplicate an already configured child fd to another child fd.
; ------------------------------------------------------------

.proc ksys_spawn_fd_dup_child
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ; Copy caller arguments before file_io_gate_acquire can block/yield.
    ldy #spawn_fd_dup_child_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ldy #spawn_fd_dup_child_args::source_fd
    lda (sched_ptr),y
    sta spawn_source_fd

    ldy #spawn_fd_dup_child_args::target_fd
    lda (sched_ptr),y
    sta spawn_target_fd

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    lda spawn_child_pid
    sta spawn_fd_clone_args + fd_clone_args::source_pid
    sta spawn_fd_clone_args + fd_clone_args::target_pid

    lda spawn_source_fd
    sta spawn_fd_clone_args + fd_clone_args::source_fd

    lda spawn_target_fd
    sta spawn_fd_clone_args + fd_clone_args::target_fd

    ldx #<spawn_fd_clone_args
    ldy #>spawn_fd_clone_args
    jsr fd_clone_between
    bcs @fail_release

    jsr file_io_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr file_io_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_fd_close
;
; Input:
;   X/Y -> spawn_fd_close_args
;
; Purpose:
;   Close one fd in the pending child.  EBADF is treated as success so
;   the setup ABI can express "ensure closed" idempotently.
; ------------------------------------------------------------

.proc ksys_spawn_fd_close
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ; Copy caller arguments before file_io_gate_acquire can block/yield.
    ldy #spawn_fd_close_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ldy #spawn_fd_close_args::child_fd
    lda (sched_ptr),y
    sta spawn_child_fd

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    ldx spawn_child_pid
    lda spawn_child_fd
    jsr fd_close_pid
    bcc @closed_ok

    cpy #EBADF
    bne @fail_release

@closed_ok:
    jsr file_io_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr file_io_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_commit
;
; Input:
;   X/Y -> spawn_child_args
;
; Purpose:
;   Publish a fully configured PROC_SETUP child as PROC_NEW.  Only the
;   parent that allocated the child may commit it.
; ------------------------------------------------------------

.proc ksys_spawn_commit
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ldy #spawn_child_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    jsr proc_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    ; Clone RP-owned CWD while the child is still PROC_SETUP. Gate order is
    ; PROC -> FILE_IO; both may remain owned while the parent waits for RP.
    jsr file_io_gate_acquire
    bcc @cwd_gate_fail
    stz io_ptr
    stz io_ptr+1
    lda #RP_FS_OP_CWD_CLONE
    ldx spawn_child_pid
    ldy active_pid
    jsr rp_fs_exec
    php
    phy
    jsr file_io_gate_release
    ply
    plp
    bcs @fail_release

    lda spawn_child_pid
    ldx spawn_child_pid
    lda #PROC_NEW
    jsr proc_set_state

    jsr proc_gate_release
    bcc @release_fail

    clc
    rts

@cwd_gate_fail:
    ldy #EAGAIN

@fail_release:
    sty spawn_errno
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_spawn_abort
;
; Input:
;   X/Y -> spawn_child_args
;
; Purpose:
;   Destroy an uncommitted PROC_SETUP child owned by active_pid.
; ------------------------------------------------------------

.proc ksys_spawn_abort
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ldy #spawn_child_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ; Close any FDs configured before abort.  The child is not
    ; runnable, and only the parent can configure it.
    jsr file_io_gate_acquire
    bcs @file_gate_acquired

    ldy #EAGAIN
    sec
    rts

@file_gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @file_fail_release

    ldx spawn_child_pid
    jsr fd_close_process
    bcs @file_fail_release

    jsr file_io_gate_release
    bcc @release_fail

    ; Clear the process/context state under proc_gate.
    jsr proc_gate_acquire
    bcs @proc_gate_acquired

    ldy #EAGAIN
    sec
    rts

@proc_gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @proc_fail_release

    ; Release the preloaded context owned by this setup child.
    ldx spawn_child_pid
    jsr ctx_free_for_pid

    ; Clear wait/signal/exit state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x
    stz proc_signal_pending,x
    lda #EXIT_OK
    sta proc_exit_code,x

    ; Clear process metadata.
    lda #$FF
    sta proc_parent_pid,x
    sta proc_context,x

    stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x
    jsr spawn_clear_launch_state_for_pid

    ; Mark empty last.
    lda #PROC_EMPTY
    jsr proc_set_state

    jsr proc_gate_release
    bcc @release_fail

    clc
    rts

@file_fail_release:
    sty spawn_errno
    jsr file_io_gate_release
    ldy spawn_errno
    sec
    rts

@proc_fail_release:
    sty spawn_errno
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
.endproc


; ------------------------------------------------------------
; ksys_spawn_set_launch_id
;
; Input:
;   X/Y -> spawn_set_launch_id_args
;
; Purpose:
;   Assign a generic one-byte launch selector to a pending child.
;   The kernel does not interpret the selector.  Resident userland
;   entry code such as nbox_child_entry defines the selector meaning.
; ------------------------------------------------------------

.proc ksys_spawn_set_launch_id
    stx sched_ptr
    sty sched_ptr+1

    ldy #spawn_set_launch_id_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ldy #spawn_set_launch_id_args::launch_id
    lda (sched_ptr),y
    sta spawn_launch_id_arg

    jsr proc_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    ldx spawn_child_pid
    lda spawn_launch_id_arg
    sta proc_launch_id,x

    jsr proc_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
    rts
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
;   its parent assigned while the child was still PROC_SETUP.
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
; ksys_spawn_set_args2
;
; Input:
;   X/Y -> spawn_set_args2_args
;
; Purpose:
;   Copy up to two parent-context argument strings into shared launch
;   storage for a pending child.
; ------------------------------------------------------------
.proc ksys_spawn_set_args2
    stx sched_ptr
    sty sched_ptr+1
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ldy #spawn_set_args2_args::child_pid
    lda (sched_ptr),y
    sta spawn_child_pid

    ldy #spawn_set_args2_args::argc
    lda (sched_ptr),y
    sta spawn_argc
    cmp #3
    bcc @argc_ok

    ldy #EINVAL
    sec
    rts

@argc_ok:
    ldy #spawn_set_args2_args::arg0_ptr
    lda (sched_ptr),y
    sta spawn_arg0_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg0_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg0_len
    cmp #SPAWN_ARG_MAX
    bcc @arg0_len_ok

    ldy #EINVAL
    sec
    rts

@arg0_len_ok:
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
    bcc @arg1_len_ok

    ldy #EINVAL
    sec
    rts

@arg1_len_ok:
    jsr proc_gate_acquire
    bcs @gate_acquired

    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    lda spawn_child_pid
    jsr spawn_validate_setup_child
    bcs @fail_release

    ldx spawn_child_pid
    lda spawn_argc
    sta proc_launch_argc,x

    ; Default no args.
    stz proc_launch_arg0_len,x
    stz proc_launch_arg1_len,x

    lda spawn_argc
    beq @done_copy

    ; Copy arg0.
    lda spawn_arg0_len
    sta proc_launch_arg0_len,x
    sta spawn_copy_len
    lda spawn_arg0_ptrL
    sta io_ptr
    lda spawn_arg0_ptrH
    sta io_ptr+1
    jsr spawn_set_arg0_dev_ptr
    jsr spawn_copy_parent_to_launch_slot

    lda spawn_argc
    cmp #2
    bne @done_copy

    ; Copy arg1.
    lda spawn_arg1_len
    sta proc_launch_arg1_len,x
    sta spawn_copy_len
    lda spawn_arg1_ptrL
    sta io_ptr
    lda spawn_arg1_ptrH
    sta io_ptr+1
    jsr spawn_set_arg1_dev_ptr
    jsr spawn_copy_parent_to_launch_slot

@done_copy:
    jsr proc_gate_release
    bcc @release_fail

    clc
    rts

@fail_release:
    sty spawn_errno
    jsr proc_gate_release
    ldy spawn_errno
    sec
    rts

@release_fail:
    ldy #EAGAIN
    sec
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
    stx spawn_arg_ptrL
    sty spawn_arg_ptrH

    ldx active_pid
    cpx #MAX_PROCS
    bcc @pid_ok

    ldy #EINVAL
    sec
    rts

@pid_ok:
    ldy #spawn_get_args2_args::arg0_ptr
    lda (sched_ptr),y
    sta spawn_arg0_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg0_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg0_max

    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrL
    iny
    lda (sched_ptr),y
    sta spawn_arg1_ptrH
    iny
    lda (sched_ptr),y
    sta spawn_arg1_max

    lda proc_launch_arg0_len,x
    cmp spawn_arg0_max
    bcc @arg0_fits

    ldy #EINVAL
    sec
    rts

@arg0_fits:
    lda proc_launch_arg1_len,x
    cmp spawn_arg1_max
    bcc @arg1_fits

    ldy #EINVAL
    sec
    rts

@arg1_fits:
    ; Copy arg0 into child-local destination.
    lda proc_launch_arg0_len,x
    sta spawn_copy_len
    lda spawn_arg0_ptrL
    sta io_ptr
    lda spawn_arg0_ptrH
    sta io_ptr+1
    jsr spawn_set_arg0_dev_ptr
    jsr spawn_copy_launch_slot_to_child

    ; Copy arg1 into child-local destination.
    ldx active_pid
    lda proc_launch_arg1_len,x
    sta spawn_copy_len
    lda spawn_arg1_ptrL
    sta io_ptr
    lda spawn_arg1_ptrH
    sta io_ptr+1
    jsr spawn_set_arg1_dev_ptr
    jsr spawn_copy_launch_slot_to_child

    ; Write result fields back to arg block.
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

    clc
    rts
.endproc
