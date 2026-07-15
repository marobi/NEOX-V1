; ============================================================
; process_control.asm
; NEOX - process control / signals
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "syscall.inc"
.include "signal.inc"
.include "context.inc"
.include "spawn.inc"

.export proc_find_free_pid
.export proc_alloc_preloaded
.export proc_alloc_preloaded_setup
.export proc_exit_lifecycle
.export proc_reap_waited_child
.export proc_create
.export proc_terminate
.export proc_send_signal
.export proc_apply_scheduler_signal
.export proc_mark_zombie
.export proc_reap_zombies

.import proc_gate_acquire
.import proc_gate_release
.import proc_gate_cancel_wait
.import proc_gate
.import proc_gate_owner
.import fd_init_process
.import fd_clear_process_slots
.import fd_close_process
.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_cancel_wait
.import file_io_gate
.import file_io_gate_owner

.import active_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_parent_pid
.import proc_signal_pending
.import proc_exit_code
.import proc_launch_id
.import proc_launch_argc
.import proc_launch_arg0_len
.import proc_launch_arg1_len
.import timer_free

.import wait_reason
.import wait_object

.import proc_set_state
.import proc_clear_wait
.import proc_wake
.import ctx_alloc_preloaded_for_pid
.import ctx_free_for_pid

.importzp sched_ptr

.segment "KERN_BSS"

proc_alloc_parent_pid:
    .res 1

proc_alloc_entryL:
    .res 1

proc_alloc_entryH:
    .res 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; proc_find_free_pid
;
; Return:
;   C set   = found, X = free pid
;   C clear = none available
;
; Notes:
;   PID 0 is reserved for idle/supervisor fallback.
; ------------------------------------------------------------

.proc proc_find_free_pid
    ldx #$01

@scan:
    lda proc_state,x
    beq @found

    inx
    cpx #MAX_PROCS
    bne @scan

    clc
    rts

@found:
    sec
    rts
.endproc


; ------------------------------------------------------------
; proc_clear_launch_state
;
; Input:
;   X = PID
;
; Purpose:
;   Clear minimal resident launch state for a process slot. The large
;   arg/cwd path blobs are not scrubbed; their lengths/selectors make
;   them inactive.
; ------------------------------------------------------------
.proc proc_clear_launch_state
    lda #SPAWN_LAUNCH_NONE
    sta proc_launch_id,x
    stz proc_launch_argc,x
    stz proc_launch_arg0_len,x
    stz proc_launch_arg1_len,x
    rts
.endproc

; ------------------------------------------------------------
; proc_alloc_preloaded
;
; Inputs:
;   A = parent PID
;   X = entry low byte
;   Y = entry high byte
;
; Return:
;   C clear = success
;             A = allocated PID
;
;   C set   = failure
;
; Notes:
;   - Caller must hold proc_gate.
;   - This routine acquires file_io_gate while initializing descriptors.
;   - Lock order is PROC -> FILE_IO.
;   - PID is allocated by the kernel.
;   - MMU context is allocated from CTX_PRELOADED_FREE slots.
;   - State is written last so partially initialized slots are never
;     visible as runnable.
;   - This is the common allocator for static boot tasks and future
;     resident/preloaded spawn.
; ------------------------------------------------------------

.proc proc_alloc_preloaded
    sta proc_alloc_parent_pid
    stx proc_alloc_entryL
    sty proc_alloc_entryH

    ; Process creation owns both allocations:
    ;   1. allocate a free PID
    ;   2. allocate a free preloaded MMU context for that PID
    ; The context table is the authority for MMU context ownership.
    jsr proc_find_free_pid
    bcc @fail

    ; X = allocated PID.  Allocate a preloaded context before
    ; publishing the process.
    jsr ctx_alloc_preloaded_for_pid
    bcs @fail

    ; Save allocated MMU context id.
    sta proc_context,x

    ; Save first-run entry address.
    lda proc_alloc_entryL
    sta proc_entryL,x

    lda proc_alloc_entryH
    sta proc_entryH,x

    ; Record parent PID.
    lda proc_alloc_parent_pid
    sta proc_parent_pid,x

    ; Initial task stack.
    lda #$FF
    sta proc_sp,x

    ; Initial wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Initial pending signal.
    stz proc_signal_pending,x

    ; Initial exit code and launch metadata.
    lda #EXIT_OK
    sta proc_exit_code,x
    jsr proc_clear_launch_state

    ; New processes are bootstrapped once. After first run, every
    ; saved runnable process frame is RTI-compatible.

    ; Initial process flags.
    lda #PROC_FLAG_NONE
    sta proc_flags,x

    ; FD/open-object tables and fd.asm shared scratch are protected by
    ; file_io_gate. Preserve the allocated PID on the private stack because
    ; file_io_gate_acquire may block/yield and returns X = active_pid.
    phx
    jsr file_io_gate_acquire
    bcs @file_gate_acquired

    plx
    jsr ctx_free_for_pid
    jmp @fail

@file_gate_acquired:
    plx
    jsr fd_init_process
    bcs @fd_fail_release

    phx
    jsr file_io_gate_release
    bcc @file_release_fail
    plx

    ; Publish process last.
    lda #PROC_NEW
    jsr proc_set_state

    txa
    clc
    rts

@fd_fail_release:
    phx
    jsr file_io_gate_release
    plx
    jsr ctx_free_for_pid
    jmp @fail

@file_release_fail:
    plx
    jsr ctx_free_for_pid

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_alloc_preloaded_setup
;
; Inputs:
;   A = parent PID
;   X = entry low byte
;   Y = entry high byte
;
; Return:
;   C clear = success
;             A = allocated PID
;
;   C set   = failure
;
; Notes:
;   - Caller must hold proc_gate.
;   - This routine acquires file_io_gate while clearing descriptors.
;   - Lock order is PROC -> FILE_IO.
;   - Allocates a PID and CTX_PRELOADED_FREE context.
;   - Leaves the child in PROC_SETUP, not runnable.
;   - The child FD table is cleared but no default fd 0/1/2 are
;     installed.  The parent-controlled spawn ABI must configure FDs
;     explicitly before spawn_commit.
; ------------------------------------------------------------

.proc proc_alloc_preloaded_setup
    sta proc_alloc_parent_pid
    stx proc_alloc_entryL
    sty proc_alloc_entryH

    jsr proc_find_free_pid
    bcc @fail

    ; X = allocated PID.  Allocate a preloaded context before
    ; publishing the process.
    jsr ctx_alloc_preloaded_for_pid
    bcs @fail

    ; Save allocated MMU context id.
    sta proc_context,x

    ; Save first-run entry address.
    lda proc_alloc_entryL
    sta proc_entryL,x

    lda proc_alloc_entryH
    sta proc_entryH,x

    ; Record parent PID.
    lda proc_alloc_parent_pid
    sta proc_parent_pid,x

    ; Initial child stack.
    lda #$FF
    sta proc_sp,x

    ; Initial wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Initial pending signal and exit code.
    stz proc_signal_pending,x
    lda #EXIT_OK
    sta proc_exit_code,x

    ; Initial process flags.
    lda #PROC_FLAG_NONE
    sta proc_flags,x

    ; Setup children start with an empty fd table. FD/open-object tables and
    ; fd.asm shared scratch are protected by file_io_gate even though the
    ; child itself is not runnable yet.
    phx
    jsr file_io_gate_acquire
    bcs @file_gate_acquired

    plx
    jsr ctx_free_for_pid
    jmp @fail

@file_gate_acquired:
    plx
    jsr fd_clear_process_slots
    bcs @fd_fail_release

    phx
    jsr file_io_gate_release
    bcc @file_release_fail
    plx

    ; Publish process last, but only as pending setup.
    lda #PROC_SETUP
    jsr proc_set_state

    txa
    clc
    rts

@fd_fail_release:
    phx
    jsr file_io_gate_release
    plx
    jsr ctx_free_for_pid
    jmp @fail

@file_release_fail:
    plx
    jsr ctx_free_for_pid

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_create
;
; Inputs:
;   X/Y = pointer to proc_create_args
;
; Return:
;   C clear = success
;             A = allocated PID
;
;   C set   = failure
;
; Notes:
;   - Static boot tasks no longer supply MMU context ids.
;   - The task table supplies an entry point and flags/reserved bytes.
;   - proc_alloc_preloaded performs the common PID/context allocation.
;   - proc_gate serializes process lifecycle syscalls.
; ------------------------------------------------------------

.proc proc_create
    stx sched_ptr
    sty sched_ptr+1

    jsr proc_gate_acquire
    bcs @gate_acquired

    ; Recursive/bad gate acquisition.  Leave process state unchanged.
    sec
    rts

@gate_acquired:

    ; Read first-run entry address from the static task table.
    ldy #proc_create_args::entry
    lda (sched_ptr),y
    tax

    iny
    lda (sched_ptr),y
    tay

    ; Static boot task parent remains the currently active PID
    ; during bootstrap.  Today this is PID 0.
    lda active_pid
    jsr proc_alloc_preloaded
    bcs @fail_release

    ; proc_gate_release may clobber X while waking a waiter.
    ; Return the allocated PID in A after releasing the gate.
    pha
    jsr proc_gate_release
    pla

    clc
    rts

@fail_release:
    jsr proc_gate_release

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_close_fds_for_pid
;
; Input:
;   X = PID
;
; Return:
;   C clear = fd table closed
;   C set   = file_io_gate could not be acquired or close failed
;
; Notes:
;   - Caller owns proc_gate for lifecycle consistency.
;   - file_io_gate serializes FD/open-object/pipe state.
;   - X is preserved on success/failure.
; ------------------------------------------------------------

.proc proc_close_fds_for_pid
    phx
    jsr file_io_gate_acquire
    bcs @gate_acquired

    plx
    sec
    rts

@gate_acquired:
    plx
    phx
    jsr fd_close_process
    php
    pha
    phx
    phy
    jsr file_io_gate_release
    ply
    plx
    pla
    plp
    plx
    rts
.endproc

; ------------------------------------------------------------
; proc_exit_lifecycle
;
; Input:
;   X = PID to exit
;   A = exit code
;
; Notes:
;   - Caller must hold proc_gate.
;   - Parent-owned children become waitable PROC_ZOMBIE entries.
;   - Processes without a live normal parent are terminated immediately.
;   - Waitable zombies keep PID/context ownership until WAITPID reaps.
; ------------------------------------------------------------

.proc proc_exit_lifecycle
    cpx #IDLE_PID
    beq @done

    cpx #MAX_PROCS
    bcs @done

    sta proc_exit_code,x

    ; A waitable child must have a live normal parent PID.
    ldy proc_parent_pid,x
    cpy #FIRST_TASK_PID
    bcc @terminate_now

    cpy #MAX_PROCS
    bcs @terminate_now

    lda proc_state,y
    cmp #PROC_EMPTY
    beq @terminate_now

    cmp #PROC_ZOMBIE
    beq @terminate_now

    ; Close child FDs at exit time.  If closing fails because the
    ; FILE_IO gate cannot be acquired recursively, keep the existing
    ; immediate termination fallback rather than publishing a zombie
    ; with live descriptors.
    jsr proc_close_fds_for_pid
    bcs @terminate_now_from_saved

    ; Clear wait/signal state on the exiting process.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x
    stz proc_signal_pending,x

    lda #PROC_ZOMBIE
    jsr proc_set_state

    ; Wake the parent only if it is waiting for exactly this child.
    ldy proc_parent_pid,x
    lda proc_state,y
    cmp #PROC_BLOCKED
    bne @done

    lda wait_reason,y
    cmp #WAIT_PROC
    bne @done

    txa
    cmp wait_object,y
    bne @done

    tya
    tax
    jsr proc_wake

@done:
    rts

@terminate_now_from_saved:
    ; Fall through to immediate termination with the stored exit code.

@terminate_now:
    lda proc_exit_code,x
    jmp proc_terminate
.endproc

; ------------------------------------------------------------
; proc_reap_waited_child
;
; Input:
;   X = child PID
;
; Return:
;   C clear = reaped, A = exit code
;   C set   = not a zombie/invalid
;
; Notes:
;   Caller must hold proc_gate and must already have validated that
;   the active process is this child's parent.
; ------------------------------------------------------------

.proc proc_reap_waited_child
    cpx #IDLE_PID
    beq @fail

    cpx #MAX_PROCS
    bcs @fail

    lda proc_state,x
    cmp #PROC_ZOMBIE
    bne @fail

    lda proc_exit_code,x
    pha

    ; proc_terminate accepts A = exit code and X = PID.  The exit code
    ; is still in A after PHA, so this preserves the final status while
    ; reusing the existing context/process cleanup path.
    jsr proc_terminate

    pla
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_terminate
;
; Input:
;   X = PID to terminate
;   A = exit code
;
; Notes:
;   - PID 0 must never be terminated.
;   - fd_close_process clobbers X.
;   - Preserve target PID with PHX/PLX.
;   - Mark PROC_EMPTY last.
; ------------------------------------------------------------

.proc proc_terminate
    cpx #IDLE_PID
    beq @done

    cpx #MAX_PROCS
    bcs @done

    ; Store exit code while X still contains target PID.
    sta proc_exit_code,x

    ; fd_close_process touches FD/open-object/pipe state.
    ; Acquire file_io_gate here because process termination is not
    ; entered through ksys_io.asm.
    phx
    jsr file_io_gate_acquire
    bcs @gate_acquired

    plx
    rts

@gate_acquired:

    ; file_io_gate_acquire clobbers X with active_pid.
    ; Restore the target PID before closing that process's FDs,
    ; but keep it saved for the rest of proc_terminate.
    plx
    phx
    jsr fd_close_process
    php
    pha
    phx
    phy
    jsr file_io_gate_release
    ply
    plx
    pla
    plp
    plx

    ; Clear wait state.
    lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x

    ; Clear pending signal and launch state.
    stz proc_signal_pending,x
    jsr proc_clear_launch_state

    ; Release the MMU context slot owned by this process.  The
    ; process lifecycle path is serialized by the PROC gate.
    jsr ctx_free_for_pid

    ; Clear execution/context fields.
    lda #$FF
    ; Mark parent invalid for an empty slot.
    sta proc_parent_pid,x
    sta proc_context,x
    
	stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x

    ; Mark parent invalid for an empty slot.
    lda #$FF
    sta proc_parent_pid,x

    ; Mark process empty last.
    lda #PROC_EMPTY
    sta proc_state,x

@done:
    rts
.endproc

; ------------------------------------------------------------
; proc_send_signal
;
; Input:
;   X = target PID
;   A = signal
;
; Return:
;   C clear = accepted
;   C set   = rejected, Y = errno
;
; Policy:
;   SIG_KILL cannot terminate a different process while that process owns
;   FILE_IO or PROC. Destroying a preempted gate owner would strand the gate.
;   Self-kill remains valid because ksys_signal releases its own PROC gate
;   before yielding away.
; ------------------------------------------------------------

.proc proc_send_signal
    cpx #IDLE_PID
    beq @fail

    cpx #MAX_PROCS
    bcs @fail

    ldy proc_state,x
    cpy #PROC_EMPTY
    beq @fail

    cpy #PROC_ZOMBIE
    beq @fail

    cpy #PROC_SETUP
    beq @fail

    cmp #SIG_KILL
    beq @kill

    sta proc_signal_pending,x

    clc
    rts

@kill:
    ; A preempted FILE_IO owner must run again to release the gate.
    cpx file_io_gate_owner
    beq @busy

    ; A different preempted PROC owner must also be allowed to finish.
    ; The active process may kill itself from ksys_signal: in that case the
    ; PROC gate is owned only by the signal syscall and is released before
    ; sched_yield, so preserve the existing self-kill behavior.
    cpx proc_gate_owner
    bne @mark_killed

    cpx active_pid
    bne @busy

@mark_killed:
    lda #$FF        ; killed by signal
    jmp proc_mark_zombie

@busy:
    ldy #EAGAIN
    sec
    rts

@fail:
    ldy #EINVAL
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_mark_zombie
;
; Input:
;   X = target PID
;   A = exit code
;
; Return:
;   C clear = process marked zombie
;   C set   = invalid target
;
; Purpose:
;   First-stage SIG_KILL handling.  This routine removes the process
;   from runnable/waitable scheduling state, but deliberately does not
;   close FDs or free the process slot.  Full cleanup is performed by
;   proc_reap_zombies from the idle/non-critical path.
; ------------------------------------------------------------

.proc proc_mark_zombie
    cpx #IDLE_PID
    beq @fail

    cpx #MAX_PROCS
    bcs @fail

    ldy proc_state,x
    cpy #PROC_EMPTY
    beq @fail

    cpy #PROC_ZOMBIE
    beq @already_zombie

    cpy #PROC_SETUP
    beq @fail

    ; Store the final exit code before the process disappears from
    ; runnable scheduling state.
    sta proc_exit_code,x

    ; SIG_KILL has now been consumed by the lifecycle layer.
    stz proc_signal_pending,x

    ; Release reason-specific wait ownership before clearing the generic
    ; wait fields. A killed FIFO gate waiter must be unlinked so gate debug
    ; state and the next wake-up cannot retain a stale zombie PID.
    lda wait_reason,x
    cmp #WAIT_TIMER
    beq @free_timer

    cmp #WAIT_LOCK
    bne @clear_wait

    lda wait_object,x
    cmp #LOCK_ID_FILE_IO
    beq @cancel_file_io_wait

    cmp #LOCK_ID_PROC
    beq @cancel_proc_wait
    bra @clear_wait

@free_timer:
    lda wait_object,x
    phx
    tax
    jsr timer_free
    plx
    bra @clear_wait

@cancel_file_io_wait:
    jsr file_io_gate_cancel_wait
    bra @clear_wait

@cancel_proc_wait:
    jsr proc_gate_cancel_wait

@clear_wait:
    jsr proc_clear_wait

    lda #PROC_ZOMBIE
    jsr proc_set_state

@already_zombie:
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; proc_reap_zombies
;
; Return:
;   C set   = one zombie was reaped
;   C clear = no work done
;
; Purpose:
;   Non-critical cleanup phase for zombie processes.  This routine is
;   called from idle_loop, not from sched_pick_next and not from the
;   scheduler signal phase.
;
; Policy:
;   - Reaps at most one zombie per call to keep idle latency bounded.
;   - Runs only when PROC and FILE_IO gates are free.
;   - Uses a short SEI window so no process can observe the manual gate
;     ownership while cleanup is in progress.
; ------------------------------------------------------------

.proc proc_reap_zombies
    ldx #FIRST_TASK_PID

@scan:
    lda proc_state,x
    cmp #PROC_ZOMBIE
    beq @candidate

    inx
    cpx #MAX_PROCS
    bne @scan

    clc
    rts

@candidate:
    ; Waitable child zombies are reaped by their live parent through
    ; SYS_WAITPID.  The idle reaper only handles orphan/system zombies.
    ldy proc_parent_pid,x
    cpy #FIRST_TASK_PID
    bcc @idle_reap_candidate

    cpy #MAX_PROCS
    bcs @idle_reap_candidate

    lda proc_state,y
    cmp #PROC_EMPTY
    beq @idle_reap_candidate

    cmp #PROC_ZOMBIE
    beq @idle_reap_candidate

    inx
    cpx #MAX_PROCS
    bne @scan

    clc
    rts

@idle_reap_candidate:
    ; Do not block idle on a sleepable gate.  If either gate is busy,
    ; skip this idle pass and try again later.
    php
    sei

    lda proc_gate
    ora file_io_gate
    bne @busy

    lda #$01
    sta proc_gate

    lda active_pid
    sta proc_gate_owner


    lda proc_exit_code,x
    jsr proc_terminate

    lda #GATE_OWNER_NONE
    sta proc_gate_owner


    stz proc_gate

    plp
    sec
    rts

@busy:
    plp
    clc
    rts
.endproc

; ------------------------------------------------------------
; proc_apply_scheduler_signal
;
; Input:
;   X = PID
;
; Return:
;   C clear = no scheduler-safe signal was applied
;   C set   = scheduler-safe signal was applied
;
; Notes:
;   This routine is called from the scheduler's explicit signal
;   phase, before runnable selection.
;
;   It is intentionally lightweight and scheduler-safe:
;     - SIG_HALT only stops runnable/non-waiting processes.
;     - SIG_CONT resumes stopped processes and clears stale wait state.
;     - SIG_KILL is not applied here.  SIG_KILL is converted to
;       PROC_ZOMBIE by proc_send_signal / proc_mark_zombie, and final
;       cleanup is done by proc_reap_zombies from idle_loop.
;
;   Signals that are not safe to apply in the scheduler phase remain
;   pending for a later process-lifecycle path.
; ------------------------------------------------------------

.proc proc_apply_scheduler_signal
    lda proc_signal_pending,x
    beq @none

    cmp #SIG_HALT
    beq @halt

    cmp #SIG_CONT
    beq @cont

    ; SIG_KILL and unknown signal values are deliberately left alone
    ; here.  The scheduler signal phase must not terminate processes
    ; or acquire subsystem gates as a picker side effect.
@none:
    clc
    rts

@halt:
    ; A runnable process may have been timer-preempted while owning a
    ; sleepable gate. Keep SIG_HALT pending until it releases that gate.
    ; Otherwise the process could be stopped permanently with protected
    ; subsystem state still owned.
    cpx file_io_gate_owner
    beq @none

    cpx proc_gate_owner
    beq @none

    lda proc_state,x
    cmp #PROC_NEW
    beq @halt_runnable

    cmp #PROC_READY
    beq @halt_runnable

    cmp #PROC_RUNNING
    beq @halt_runnable

    ; Do not stop blocked/empty/stopped processes here.  A blocked
    ; process keeps SIG_HALT pending until its wait condition wakes it
    ; and it becomes READY; then the scheduler signal phase can stop it
    ; without corrupting wait_reason/wait_object semantics.
    clc
    rts

@halt_runnable:
    stz proc_signal_pending,x
    jsr proc_clear_wait

    lda #PROC_STOPPED
    jsr proc_set_state

    sec
    rts

@cont:
    lda proc_state,x
    cmp #PROC_STOPPED
    beq @cont_stopped

    ; CONT for a non-stopped process is consumed as a no-op.  This
    ; matches the current small signal model and prevents a stale CONT
    ; byte from being applied later to an unrelated state transition.
    stz proc_signal_pending,x
    sec
    rts

@cont_stopped:
    stz proc_signal_pending,x
    jsr proc_clear_wait

    lda #PROC_READY
    jsr proc_set_state

    sec
    rts
.endproc

