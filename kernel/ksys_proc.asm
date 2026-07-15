; ============================================================
; ksys_proc.asm
; NEOX - kernel-owned process lifecycle syscall services
;
; The syscall page only jumps here. Process lifecycle state is
; owned by the kernel, not by the syscall veneer.
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "syscall.inc"
.include "timer.inc"
.include "signal.inc"
.include "scheduler_defs.inc"

.export ksys_exit
.export ksys_yield
.export ksys_sleep
.export ksys_signal
.export ksys_getprocinfo
.export ksys_waitpid

.import idle_loop
.import proc_exit_current
.import sched_yield
.import sched_block_current
.import proc_set_wait

.import timer_start_current
.import proc_send_signal
.import proc_reap_waited_child
.import proc_gate_acquire
.import proc_gate_release
.import active_pid
.importzp io_ptr
.import proc_state
.import proc_parent_pid
.import proc_signal_pending
.import wait_reason
.import wait_object
.import file_io_gate_owner
.import proc_gate_owner


.segment "KERN_BSS"

; Protected by proc_gate while ksys_signal is executing.
ksys_signal_self_kill:
    .res 1

.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_exit
;
; Input:
;   A = exit code
;
; Purpose:
;   Terminate the current process.
;
; Current scheduler model:
;   After marking this process dead, execution must not continue
;   into user code. Transfer to the idle loop until the scheduler
;   selects another runnable process.
; ------------------------------------------------------------

.proc ksys_exit
    jsr proc_exit_current

	jmp idle_loop
.endproc

; ------------------------------------------------------------
; ksys_yield
;
; Purpose:
;   Voluntary yield syscall.
;
; Current model:
;   Cooperative scheduling enters the same scheduler handoff path
;   used by preemptive scheduling.
; ------------------------------------------------------------

.proc ksys_yield
    jmp sched_yield
.endproc

; ------------------------------------------------------------
; ksys_sleep
;
; Input:
;   A = relative sleep ticks
;
; Purpose:
;   Block current process until timer expiration.
;
; Notes:
;   timer_start_current reserves and arms a timer slot only.
;   sched_block_current owns the actual process block transition.
; ------------------------------------------------------------

.proc ksys_sleep
    cmp #0
    beq @done

    jsr timer_start_current
    bcs @fail

    ; Y = armed timer slot.  The scheduler-owned block primitive
    ; saves the syscall continuation first, then commits WAIT_TIMER.
    lda #WAIT_TIMER
    jmp sched_block_current

@fail:
    ldy #EAGAIN
    sec
    rts

@done:
    clc
    rts
.endproc


; ------------------------------------------------------------
; ksys_signal
;
; Input:
;   A = signal number (SIG_HALT, SIG_CONT, SIG_KILL)
;   X = target PID
;
; Return:
;   C clear = signal accepted
;   C set   = failure
;   Y       = errno
;
; Notes:
;   proc_gate serializes the process-table write performed by
;   proc_send_signal.  Arguments are preserved on the current
;   process stack while proc_gate_acquire may block/yield.
;
;   This syscall queues HALT/CONT as pending signals.  SIG_KILL is
;   converted immediately to PROC_ZOMBIE through proc_send_signal;
;   final FD/process-slot cleanup is deferred to the idle reaper.
; ------------------------------------------------------------

.proc ksys_signal
    cmp #SIG_HALT
    beq @valid_signal

    cmp #SIG_CONT
    beq @valid_signal

    cmp #SIG_KILL
    beq @valid_signal

    ldy #EINVAL
    sec
    rts

@valid_signal:
    ; Preserve syscall arguments across proc_gate_acquire.  The gate
    ; may block and yield; the current process stack is the safe place
    ; to keep these per-call values.
    pha             ; signal
    txa
    pha             ; target PID

    jsr proc_gate_acquire
    bcs @gate_acquired

    ; Recursive/bad gate acquisition.  Drop saved arguments.
    pla
    pla
    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    stz ksys_signal_self_kill

    pla
    tax             ; target PID
    pla             ; signal

    ; If the caller sends SIG_KILL to itself, proc_send_signal marks
    ; the active process PROC_ZOMBIE.  After releasing proc_gate the
    ; syscall must not return to user code; it yields out instead.
    cmp #SIG_KILL
    bne @send_signal

    pha
    txa
    cmp active_pid
    bne @not_self_kill

    lda #$01
    sta ksys_signal_self_kill

@not_self_kill:
    pla

@send_signal:
    jsr proc_send_signal
    bcs @invalid_target

    jsr proc_gate_release
    bcs @released

    ldy #EAGAIN
    sec
    rts

@released:
    lda ksys_signal_self_kill
    bne @yield_zombie

    clc
    rts

@yield_zombie:
    jmp sched_yield

@invalid_target:
    ; proc_send_signal returns the specific rejection reason in Y. Preserve
    ; it across gate release so a protected gate owner reports EAGAIN rather
    ; than being misreported as an invalid PID.
    phy
    jsr proc_gate_release
    ply
    sec
    rts
.endproc


; ------------------------------------------------------------
; ksys_waitpid
;
; Input:
;   A = child PID
;
; Return:
;   C clear = child reaped
;             A = child exit code
;
;   C set   = failure
;             Y = errno
;
; Purpose:
;   Wait for a specific child owned by the active parent.  If the
;   child is not yet a zombie, block on WAIT_PROC / child_pid and
;   retry after wake.
;
; Notes:
;   The requested child PID is kept on the current process stack across
;   proc_gate acquisition and sched_yield.  Do not use module-global
;   scratch for this value because another process can enter WAITPID
;   while this one is blocked.
; ------------------------------------------------------------
.proc ksys_waitpid
    pha                         ; persistent requested child PID

@retry:
    jsr proc_gate_acquire
    bcs @gate_acquired

    pla                         ; discard child PID
    ldy #EAGAIN
    sec
    rts

@gate_acquired:
    ; Reload requested child PID without removing the persistent copy.
    pla
    pha

    cmp #MAX_PROCS
    bcc @pid_range_ok

    ldy #EINVAL
    jmp @fail_release

@pid_range_ok:
    tax
    cpx #IDLE_PID
    bne @not_idle

    ldy #EINVAL
    jmp @fail_release

@not_idle:
    lda proc_parent_pid,x
    cmp active_pid
    beq @owned_child

    ldy #EINVAL
    jmp @fail_release

@owned_child:
    lda proc_state,x
    cmp #PROC_ZOMBIE
    beq @reap_child

    cmp #PROC_EMPTY
    beq @invalid_state

    cmp #PROC_SETUP
    beq @invalid_state

    ; Child is still alive.  Commit the wait state while proc_gate is
    ; held, then release the gate and yield immediately with IRQs
    ; masked so no child-exit wake can be lost in between.
    sei

    pla
    tay                         ; wait_object = child PID
    pha                         ; keep child PID for retry after wake

    ldx active_pid
    lda #WAIT_PROC
    jsr proc_set_wait

    jsr proc_gate_release

    jsr sched_yield
    jmp @retry

@invalid_state:
    ldy #EINVAL
    jmp @fail_release

@reap_child:
    ; X = child PID.  Reap under proc_gate, then return the stored
    ; exit code to the parent.
    jsr proc_reap_waited_child
    bcc @reaped

    ldy #EINVAL
    jmp @fail_release

@reaped:
    pha                         ; exit code above persistent child PID
    jsr proc_gate_release
    bcc @release_fail_after_reap

    pla                         ; A = exit code
    tax                         ; preserve in X while dropping child PID
    pla                         ; discard persistent child PID
    txa                         ; A = exit code
    clc
    rts

@fail_release:
    tya                         ; save errno above persistent child PID
    pha
    jsr proc_gate_release
    pla
    tay
    pla                         ; discard persistent child PID
    sec
    rts

@release_fail_after_reap:
    pla                         ; discard exit code
    pla                         ; discard persistent child PID
    ldy #EAGAIN
    sec
    rts
.endproc

; ------------------------------------------------------------
; ksys_getprocinfo
;
; Input:
;   X/Y = procinfo_args pointer
;
; Return:
;   C clear = record copied
;   C set   = failure
;   Y       = errno
;
; Purpose:
;   Copy one compact process-table snapshot record for user-space PS.
;
; Record layout:
;   +0 pid
;   +1 ppid
;   +2 state
;   +3 wait_reason
;   +4 signal_pending
;   +5 wait_object
;   +6 held_gate_mask
;
; Notes:
;   This is a small diagnostic syscall. It keeps IRQs disabled while
;   reading process and gate state. Callers supplying the original
;   five-byte buffer receive the original record; buffers of seven bytes
;   or more receive the wait object and derived gate-hold mask as well.
; ------------------------------------------------------------
.proc ksys_getprocinfo
    php
    sei

    stx io_ptr
    sty io_ptr+1

    ldy #procinfo_args::pid
    lda (io_ptr),y
    cmp #MAX_PROCS
    bcc @pid_ok
    plp
    cli
    ldy #EINVAL
    sec
    rts

@pid_ok:
    tax

    ; Preserve compatibility with the original five-byte record. A
    ; seven-byte or larger buffer receives the extended diagnostic fields.
    ldy #procinfo_args::buffer_size + 1
    lda (io_ptr),y
    bne @extended_size

    dey
    lda (io_ptr),y
    cmp #PROCINFO_RECORD_MIN_SIZE
    bcc @size_fail

    cmp #PROCINFO_RECORD_SIZE
    bcs @extended_size

    lda #$00
    bra @save_size_mode

@extended_size:
    lda #$01

@save_size_mode:
    pha                         ; 0 = legacy record, 1 = extended record
    bra @size_ok

@size_fail:
    plp
    cli
    ldy #EINVAL
    sec
    rts

@size_ok:
    ldy #procinfo_args::buffer_ptr
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    sta io_ptr+1
    pla
    sta io_ptr

    ldy #0
    txa
    sta (io_ptr),y
    iny

    lda proc_parent_pid,x
    sta (io_ptr),y
    iny

    lda proc_state,x
    sta (io_ptr),y
    iny

    lda wait_reason,x
    sta (io_ptr),y
    iny

    lda proc_signal_pending,x
    sta (io_ptr),y

    pla                         ; extended-record flag
    beq @record_done

    iny
    lda wait_object,x
    sta (io_ptr),y

    iny
    lda #PROC_HOLD_NONE

    cpx file_io_gate_owner
    bne @not_file_io_owner
    ora #PROC_HOLD_FILE_IO

@not_file_io_owner:
    cpx proc_gate_owner
    bne @hold_mask_ready
    ora #PROC_HOLD_PROC

@hold_mask_ready:
    sta (io_ptr),y

@record_done:
    plp
    cli
    clc
    rts
.endproc
