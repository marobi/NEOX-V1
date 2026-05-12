; ============================================================
; scheduler.asm
; NEOX - timer-driven scheduler core
;
; Purpose:
;   Implements process scheduling and context switching.
;
; Architecture:
;   - PID 0 = idle process
;   - PID 0 is the fallback runnable process
;   - normal tasks are PID 1..MAX_PROCS-1
;   - monitor/supervisor uses context 0 directly, not a PID
;
; Blocking model:
;   - A task may mark itself PROC_BLOCKED.
;   - The IRQ scheduler skips PROC_BLOCKED tasks.
;   - External readiness events wake blocked tasks by changing
;     them back to PROC_READY.
;   - sched_context_switch is IRQ-only.
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "process.inc"
.include "mailbox.inc"
.include "scheduler_defs.inc"

.export scheduler_init
.export scheduler_set_current_context
.export scheduler_create_process
.export sched_pick_next
.export sched_context_switch
.export sched_yield
.export sched_resume_rts
.export first_run_entry

.export proc_set_state
.export proc_set_ready
.export proc_set_running
.export proc_wake
.export scheduler_wake_console_input

.export proc_set_wait
.export proc_clear_wait
.export proc_exit_current

.import sched_lock_enter
.import sched_lock_leave

.import fd_init_process
.import fd_close_process

.import current_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_resume_mode

.import sched_lock
.import console_owner_pid
.import monitor_return_mode

.importzp sched_ptr

.import wait_reason
.import wait_object

.import proc_exit_code

.import timer_init
.import scheduler_tick
.import scheduler_wake_timers

.import proc_ticks_lo
.import proc_ticks_hi

.segment "KERN_TEXT"

; ------------------------------------------------------------
; proc_set_state
;
; Input:
;   X = pid
;   A = state
; ------------------------------------------------------------

.proc proc_set_state
    sta proc_state,x
    rts
.endproc

; ------------------------------------------------------------
; proc_set_ready
;
; Input:
;   X = pid
; ------------------------------------------------------------

.proc proc_set_ready
    lda #PROC_READY
    jmp proc_set_state
.endproc

; ------------------------------------------------------------
; proc_set_running
;
; Input:
;   X = pid
; ------------------------------------------------------------

.proc proc_set_running
    lda #PROC_RUNNING
    jmp proc_set_state
.endproc

; ------------------------------------------------------------
; proc_wake
;
; Input:
;   X = pid
;
; Purpose:
;   Wake a blocked process:
;     - clear its wait reason/object
;     - mark it READY
;
; Notes:
;   The caller decides that the wait condition is satisfied.
; ------------------------------------------------------------

.proc proc_wake
    jsr proc_clear_wait
    jmp proc_set_ready
.endproc

; ------------------------------------------------------------
; proc_set_wait
;
; Mark process X blocked on wait reason A / object Y.
;
; PID 0 is the idle task and must never enter a wait state.
; If idle blocks, the scheduler has no guaranteed fallback task.
; ------------------------------------------------------------
.proc proc_set_wait
    cpx #IDLE_PID
    beq @done

    sta wait_reason,x
    tya
    sta wait_object,x

    lda #PROC_BLOCKED
    sta proc_state,x

@done:
    rts
.endproc

; ------------------------------------------------------------
; proc_clear_wait
;
; Input:
;   X = pid
;
; Purpose:
;   Clear the wait reason/object for a process.
;
; Notes:
;   This does not change proc_state. The caller decides whether
;   the process becomes READY, RUNNING, etc.
; ------------------------------------------------------------

.proc proc_clear_wait
    lda #WAIT_NONE
    sta wait_reason,x

    stz wait_object,x

    rts
.endproc

; ------------------------------------------------------------
; proc_exit_current
;
; Input:
;   A = exit code
;
; Purpose:
;   Terminate the currently running process.
;
; Current model:
;   - no parent/child tracking yet
;   - no zombie state yet
;   - exit code currently ignored
;
; Effects:
;   - closes all process file descriptors
;   - clears wait state
;   - marks process slot EMPTY
;
; Notes:
;   Caller must not return to user code afterwards.
; ------------------------------------------------------------

.proc proc_exit_current
    ldx current_pid

    ; If the exiting process owns the console, release ownership.
    ; Do not transfer ownership to whatever process runs next.
    cpx console_owner_pid
    bne @console_done

    lda #$FF
    sta console_owner_pid

@console_done:
    jsr fd_close_process
    jsr proc_clear_wait

    lda #PROC_EMPTY
    jsr proc_set_state

    jmp sched_yield
.endproc

; ------------------------------------------------------------
; proc_accounting_init
;
; Clear per-process runtime counters.
;
; This must run during scheduler/process initialization before
; the timer IRQ is enabled. Once IRQ accounting starts, these
; counters are updated from interrupt context and must not be
; cleared casually.
;
; Clobbers:
;   X
; ------------------------------------------------------------
.proc proc_accounting_init
    ldx #MAX_PROCS - 1

@clear_proc:
    stz proc_ticks_lo,x
    stz proc_ticks_hi,x

    dex
    bpl @clear_proc

    rts
.endproc

; ------------------------------------------------------------
; sched_account_tick
;
; Account one scheduler tick to the currently running process.
;
; PID 0 is the idle task. System idle time is therefore equal
; to proc_ticks[0].
;
; Called from timer IRQ context.
;
; Clobbers:
;   X
; ------------------------------------------------------------
.proc sched_account_tick
    ldx current_pid

    inc proc_ticks_lo,x
    bne @done

    inc proc_ticks_hi,x

@done:
    rts
.endproc

; ------------------------------------------------------------
; sched_update_console_focus
;
; Purpose:
;   Synchronize console ownership with RP console focus state.
;
; Model:
;   RP_CONSOLE_PID is authoritative and controlled only by the
;   RP2350 side.
;
; Policy:
;   - $FF = no focused task
;   - 0   = monitor/supervisor focus
;   - >0  = foreground process
;
; Safety:
;   If RP points at an EMPTY process slot, ownership is cleared.
; ------------------------------------------------------------

.proc sched_update_console_focus
    lda RP_CONSOLE_PID

    ; --------------------------------------------------------
    ; No focused task.
    ; --------------------------------------------------------

    cmp #$FF
    beq @clear_focus

    ; --------------------------------------------------------
    ; Monitor/supervisor owns console.
    ; --------------------------------------------------------

    cmp #0
    beq @clear_focus

    ; --------------------------------------------------------
    ; Validate PID range.
    ; --------------------------------------------------------

    cmp #MAX_PROCS
    bcs @clear_focus

    ; --------------------------------------------------------
    ; Reject EMPTY process slots.
    ; --------------------------------------------------------

    tax
    lda proc_state,x
    cmp #PROC_EMPTY
    beq @clear_focus

    ; --------------------------------------------------------
    ; Valid live PID.
    ; --------------------------------------------------------

    txa
    bra @set_focus

@clear_focus:
    lda #$FF

@set_focus:
    sta console_owner_pid
    rts
.endproc

; ------------------------------------------------------------
; scheduler_wake_console_input
;
; Wake the console owner if it is blocked on console input.
;
; RP_CONSOLE_RDY only means input may be available. The woken
; process must retry the actual console read after resuming.
;
; This routine does not consume input.
; ------------------------------------------------------------

.proc scheduler_wake_console_input
    lda RP_CONSOLE_RDY
    beq @done

    ldx console_owner_pid
    cpx #$FF
    beq @done

    cpx #FIRST_TASK_PID
    bcc @done

    cpx #MAX_PROCS
    bcs @done

    lda proc_state,x
    cmp #PROC_BLOCKED
    bne @done

    lda wait_reason,x
    cmp #WAIT_CONSOLE
    bne @done

    jmp proc_wake

@done:
    rts
.endproc

; ------------------------------------------------------------
; scheduler_init
;
; Purpose:
;   Initialize scheduler state.
;
; Boot policy:
;   Boot starts in pid 0 (supervisor context).
; ------------------------------------------------------------

.proc scheduler_init
	jsr proc_accounting_init
	
    stz current_pid
    stz sched_lock
    stz monitor_return_mode

    lda #$FF
    sta console_owner_pid

    ldx #$00

@clear:
    stz proc_state,x
    stz proc_context,x
    stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x
	stz proc_resume_mode,x
    
	lda #WAIT_NONE
    sta wait_reason,x
    stz wait_object,x
	
	stz proc_exit_code,x
	
    inx
    cpx #MAX_PROCS
    bne @clear

    ; --------------------------------------------------------
    ; Initialize PID 0 as idle descriptor.
    ;
    ; It becomes PROC_RUNNING in kernel_main because kernel_main
    ; is already executing the idle/supervisor loop in context 0.
    ; --------------------------------------------------------
    lda #$00
    sta proc_context+IDLE_PID

    lda #$FF
    sta proc_sp+IDLE_PID

    lda #PROC_FLAG_IDLE
    sta proc_flags+IDLE_PID

	jsr timer_init
    rts
.endproc

; ------------------------------------------------------------
; scheduler_set_current_context
;
; Input:
;   A = context id
; ------------------------------------------------------------

.proc scheduler_set_current_context
    ldx current_pid
    sta proc_context,x
    rts
.endproc

; ------------------------------------------------------------
; find_free_pid
;
; Return:
;   C set   = found, X = free pid
;   C clear = none available
; ------------------------------------------------------------

.proc find_free_pid
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
; scheduler_create_process
;
; Inputs:
;   X/Y = pointer to proc_create_args
;
; Return:
;   C clear = success, A = allocated pid
;   C set   = failure
;
; Notes:
;   - PID is allocated by the system.
;   - context 0 defines monitor.
;   - state is written last so partially initialized slots are
;     never visible as runnable.
; ------------------------------------------------------------

.proc scheduler_create_process
    stx sched_ptr
    sty sched_ptr+1

    ; Context 0 is reserved for idle/supervisor/monitor.
    ; Normal processes must not be created in context 0.
    ldy #proc_create_args::context
    lda (sched_ptr),y
    beq @fail

    jsr find_free_pid
    bcc @fail

    jsr sched_lock_enter

    ; Save MMU context id.
    ldy #proc_create_args::context
    lda (sched_ptr),y
    sta proc_context,x

    ; Save first-run entry address.
    ldy #proc_create_args::entry
    lda (sched_ptr),y
    sta proc_entryL,x

    iny
    lda (sched_ptr),y
    sta proc_entryH,x

    ; Initial task stack.
    lda #$FF
    sta proc_sp,x

	; Initial wait state
	lda #WAIT_NONE
	sta wait_reason,x
	stz wait_object,x
    
	; Initial process flags.
    lda #PROC_FLAG_NONE
    sta proc_flags,x

	; Initialise FD list
	jsr fd_init_process
    
    ; Publish process last.
    lda #PROC_NEW
    jsr proc_set_state

	; free scheduler
	jsr sched_lock_leave
	
    txa
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; sched_pick_next
;
; Purpose:
;   Select the next runnable task.
;
; Return:
;   C set   = found runnable task, X = pid
;   C clear = none found
;
; Runnable states:
;   PROC_NEW
;   PROC_READY
;
; Non-runnable states:
;   PROC_EMPTY
;   PROC_RUNNING
;   PROC_BLOCKED
;
; Notes:
;   - PID 0 is excluded from normal scheduling.
;   - Bounded scan prevents infinite loop when current_pid = 0.
;   - Uses sched_ptr as a temporary 1-byte scan counter.
;   - Clobbers sched_ptr.
; ------------------------------------------------------------

.proc sched_pick_next
    ldx current_pid

    cpx #FIRST_TASK_PID
    bcc @start_first

    inx
    cpx #MAX_PROCS
    bne @set_count

@start_first:
    ldx #FIRST_TASK_PID

@set_count:
    lda #(MAX_PROCS - FIRST_TASK_PID)
    sta sched_ptr

@check:
    lda proc_state,x

    cmp #PROC_NEW
    beq @found

    cmp #PROC_READY
    beq @found

    dec sched_ptr
    beq @idle

    inx
    cpx #MAX_PROCS
    bne @check

    ldx #FIRST_TASK_PID
    bra @check

@idle:
    ldx #IDLE_PID
    sec
    rts

@found:
    sec
    rts
.endproc

; ------------------------------------------------------------
; sched_context_switch
;
; Purpose:
;   IRQ-driven context switch.
;
; Stack model:
;   Entered from IRQ path. The saved process stack contains an
;   IRQ/RTI-compatible frame.
;
; Policy:
;   - Always account the timer tick.
;   - If sched_lock != 0, do not switch tasks.
;   - Otherwise:
;       save current SP
;       mark saved stack as RTI-resumable
;       convert current RUNNING process to READY
;       wake pending events
;       pick next runnable process
;       resume next process using its recorded resume mode
;
; Important:
;   sched_lock protects kernel critical sections. IRQs may still
;   occur while sched_lock is nonzero, but task switching must
;   not happen then.
; ------------------------------------------------------------

.proc sched_context_switch
    jsr sched_account_tick

    ; --------------------------------------------------------
    ; Scheduler locked:
    ;
    ; The interrupted process is inside a kernel critical
    ; section. Save its IRQ stack state, but do not change
    ; process state and do not select another process.
    ;
    ; This prevents cases where a process is switched away while
    ; mailbox/status/lock cleanup is only half complete.
    ; --------------------------------------------------------
    lda sched_lock
    beq @normal_switch

    ldy current_pid

    tsx
    txa
    sta proc_sp,y

    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    lda proc_context,y
    jmp BIOS_CONTEXT_RTI

@normal_switch:
    ; Save interrupted SP for current PID.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; This stack was saved from IRQ context.
    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    ; IRQ preemption: RUNNING -> READY.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    tya
    tax
    jsr proc_set_ready

@wake_events:
    jsr scheduler_tick
    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

@pick:
    jsr sched_pick_next

    ; X = selected PID, including possible IDLE fallback.
    stx current_pid

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; Resume existing process.
    jsr proc_set_running

    lda proc_sp,x
    tax
    txs

    ; Select RTI or RTS resume based on saved stack type.
    ldx current_pid
    lda proc_resume_mode,x
    cmp #PROC_RESUME_RTS
    beq @resume_rts

@resume_rti:
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@resume_rts:
    lda proc_context,x
    ldx #<sched_resume_rts
    ldy #>sched_resume_rts
    jmp BIOS_CONTEXT_JUMP

@start_new:
    jsr proc_set_running

    lda proc_context,x
    ldx #<first_run_entry
    ldy #>first_run_entry
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; sched_yield
;
; Purpose:
;   Voluntary scheduler handoff from syscall/user-call context.
;
; Stack model:
;   This is NOT an IRQ path.
;   The saved stack contains an RTS-compatible return frame.
;
; Used by:
;   sys_yield
;   sys_sleep after marking current process BLOCKED
;   future blocking syscalls
;
; Important:
;   This routine does not wake timers or console waiters.
;   Event wakeups belong to the IRQ scheduler path.
; ------------------------------------------------------------

.proc sched_yield
    ; Save current syscall/user stack pointer.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; This stack was saved from syscall/user context.
    lda #PROC_RESUME_RTS
    sta proc_resume_mode,y

    ; If the caller is still RUNNING, make it READY.
    ; Blocking syscalls set PROC_BLOCKED before calling this,
    ; so blocked tasks must remain blocked.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @pick

    tya
    tax
    jsr proc_set_ready

@pick:
    jsr sched_pick_next

    ; X = selected PID, including possible IDLE fallback.
    stx current_pid

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; Resume existing process.
    jsr proc_set_running

    lda proc_sp,x
    tax
    txs

    ; Resume through the stack format recorded for this PID.
    ldx current_pid
    lda proc_resume_mode,x
    cmp #PROC_RESUME_RTS
    beq @resume_rts

@resume_rti:
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@resume_rts:
    lda proc_context,x
    ldx #<sched_resume_rts
    ldy #>sched_resume_rts
    jmp BIOS_CONTEXT_JUMP

@start_new:
    jsr proc_set_running

    lda proc_context,x
    ldx #<first_run_entry
    ldy #>first_run_entry
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; first_run_entry
;
; Purpose:
;   Inline first-run bootstrap for PROC_NEW tasks.
;
; Behavior:
;   - reset private stack
;   - enable IRQs explicitly
;   - load entry address from process arrays
;   - jump to process entry
;
; Notes:
;   Arrives here only after BIOS_CONTEXT_JUMP has already
;   switched the MMU context. This routine never returns.
; ------------------------------------------------------------

.proc first_run_entry
    ; Start with a clean private stack.
    ldx #$FF
    txs

    ; Resolve entry address into private zero-page sched_ptr.
    ldx current_pid
    lda proc_entryL,x
    sta sched_ptr
    lda proc_entryH,x
    sta sched_ptr+1

    ; First-run path does not restore P via RTI.
    cld
	cli

    jmp (sched_ptr)
.endproc

; ------------------------------------------------------------
; sched_resume_rts
;
; Purpose:
;   Resume a task suspended from syscall/yield context.
;
; Stack:
;   Restored process stack contains the original RTS return
;   address from the blocking syscall.
; ------------------------------------------------------------

.proc sched_resume_rts
    rts
.endproc
