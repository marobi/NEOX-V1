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

.export ksys_exit
.export ksys_yield
.export ksys_sleep
.export ksys_signal

.import idle_loop
.import proc_exit_current
.import sched_yield
.import sched_block_current

.import timer_start_current
.import proc_send_signal
.import proc_gate_acquire
.import proc_gate_release
.import active_pid


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
    jsr proc_gate_release
    ldy #EINVAL
    sec
    rts
.endproc
