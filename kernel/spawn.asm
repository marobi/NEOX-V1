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

.export ksys_spawn_alloc_resident
.export ksys_spawn_fd_inherit
.export ksys_spawn_fd_dup_child
.export ksys_spawn_fd_close
.export ksys_spawn_commit
.export ksys_spawn_abort

.export spawn_validate_setup_child

.import proc_gate_acquire
.import proc_gate_release
.import file_io_gate_acquire
.import file_io_gate_release

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
.import wait_reason
.import wait_object

.importzp sched_ptr

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

    jsr proc_gate_release
    bcs @released_ok

    ldy #EAGAIN
    sec
    rts

@released_ok:
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

    lda #PROC_NEW
    jsr proc_set_state

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
