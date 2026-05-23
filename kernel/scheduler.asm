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

;---------------------------------------------

.import sched_ticks_lo
.import sched_ticks_hi

.import sched_debug_marker
.import sched_debug_pid
.import sched_debug_old_pid
.import sched_debug_old_state
.import sched_debug_state_pid
.import sched_debug_state_old
.import sched_debug_state_new
;---------------------------------------------

.import idle_loop

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
.import proc_parent_pid
.import proc_signal_pending

.import sched_lock
.import console_owner_pid
.import monitor_pending
.import supervisor_try_enter_pending

.importzp sched_ptr

.import wait_reason
.import wait_object

.import proc_apply_signal
.import proc_terminate

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
;   X = PID
;   A = new state
;
; ------------------------------------------------------------

.proc proc_set_state
    sta sched_debug_state_new

    stx sched_debug_state_pid

    lda proc_state,x
    sta sched_debug_state_old

    lda sched_debug_state_new
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
;   X = selected PID
;
; Purpose:
;   Commit X as the current running process.
;
; Policy:
;   PROC_RUNNING is exclusive. On a single CPU, only current_pid
;   may be RUNNING.
;
;   This routine owns the transition:
;
;       old current_pid -> READY, if it was RUNNING
;       selected X      -> RUNNING
;       current_pid     -> X
;
; Important:
;   Call this before loading the selected process stack/context.
; ------------------------------------------------------------

.proc proc_set_running
    phx

    ; Demote old current_pid if it is a normal running task.
    ldx current_pid
    cpx #IDLE_PID
    beq @set_selected

    lda proc_state,x
    cmp #PROC_RUNNING
    bne @set_selected

    lda #PROC_READY
    jsr proc_set_state

@set_selected:
    ; Restore selected PID.
    plx

    lda #PROC_RUNNING
    jsr proc_set_state

    stx current_pid
    rts
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
; ------------------------------------------------------------

.proc proc_exit_current
    ldx current_pid
    cpx #IDLE_PID
    beq @yield

    jsr proc_terminate

@yield:
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
    stz sched_ticks_lo
    stz sched_ticks_hi

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
    inc sched_ticks_lo
    bne @proc_tick

    inc sched_ticks_hi

@proc_tick:
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
    stz monitor_pending

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
	stz proc_signal_pending
	
    lda #$FF
	sta proc_parent_pid,x
	
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
    jsr proc_apply_signal

    lda proc_state,x

    ; DEBUG-BEGIN: sched_pick_next candidate state
    stx sched_debug_state_pid
    sta sched_debug_state_old
    ; DEBUG-END: sched_pick_next candidate state
	
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
    ; No PROC_NEW or PROC_READY task was found.
    ; That is only valid if no normal task is still PROC_RUNNING.
    ;
    ; If a normal task is PROC_RUNNING here, scheduler state is
    ; corrupt: that PID should have been demoted to PROC_READY
    ; before this scan.
    ldx #FIRST_TASK_PID

@scan_stale_running:
    lda proc_state,x
    cmp #PROC_RUNNING
    beq @stale_running

    inx
    cpx #MAX_PROCS
    bne @scan_stale_running

    ldx #IDLE_PID
    sec
    rts

@stale_running:
    ; DEBUG-BEGIN: stale RUNNING diagnostic
    stx sched_debug_state_pid
    lda proc_state,x
    sta sched_debug_state_old

    lda #$EE
    sta sched_debug_marker
    ; DEBUG-END: stale RUNNING diagnostic

    ; DEBUG-BEGIN: halt on illegal scheduler state
@halt:
    bra @halt
    ; DEBUG-END: halt on illegal scheduler state

@found:
    sec
    rts
.endproc

; ------------------------------------------------------------
; sched_context_switch
;
; IRQ/timer scheduler entry.
;
; Called from IRQ context. The current task stack is saved as
; RTI-style state because the interrupted frame contains the
; CPU IRQ return frame.
;
; Stack model:
;   irq_entry has pushed A/X/Y before entering the scheduler.
;   The saved SP therefore points at the scheduler/IRQ save
;   frame for the interrupted task.
; ------------------------------------------------------------

.proc sched_context_switch
    lda #$01
    sta sched_debug_marker

    lda current_pid
    sta sched_debug_pid

    jsr sched_account_tick

    ; Current interrupted owner.
    ldy current_pid

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    ; --------------------------------------------------------
    ; PID 0 is not a normal task.
    ;
    ; Do not save proc_sp[0].
    ; Do not set proc_resume_mode[0].
    ; Do not convert PID 0 to READY.
    ; --------------------------------------------------------

    cpy #IDLE_PID
    beq @wake_events

    ; Save interrupted SP for normal task.
    tsx

    ; DEBUG-BEGIN: sched_context_switch save interrupted owner SP
    ;
    ; sched_debug_old_pid   = PID whose IRQ stack is being saved
    ; sched_debug_state_old = SP observed at IRQ scheduler entry
    ;
    ; If a task stack leaks under timer preemption, this value
    ; will move downward before the scheduler stores it in
    ; proc_sp[].
    ; DEBUG-END: sched_context_switch save interrupted owner SP
    sty sched_debug_old_pid
    stx sched_debug_state_old

    txa
    sta proc_sp,y

    ; This stack was saved from IRQ context.
    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    ; IRQ preemption: RUNNING -> READY.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    lda #$02
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    tya
    tax
    jsr proc_set_ready

    lda proc_state,x
    sta sched_debug_old_state

@wake_events:
    jsr scheduler_tick
    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

@pick:
    jsr sched_pick_next

    lda #$03
    sta sched_debug_marker

    txa
    sta sched_debug_pid

    ; PID 0 is entered directly, not through proc_sp[0].
    cpx #IDLE_PID
    beq @resume_idle

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; Resume existing normal process.
    ;
    ; proc_set_running commits:
    ;   old current_pid -> READY, if applicable
    ;   selected X      -> RUNNING
    ;   current_pid     -> X
    ;
    ; It returns with X = current_pid.
    jsr proc_set_running

    ; DEBUG-BEGIN: sched_context_switch resume target SP
    ;
    ; sched_debug_state_pid = PID selected for resume
    ; sched_debug_state_new = saved SP loaded from proc_sp[PID]
    ;
    ; If this shows a low SP, the IRQ scheduler is restoring a
    ; stack value that was already saved low earlier.
    ; DEBUG-END: sched_context_switch resume target SP
    stx sched_debug_state_pid
    lda proc_sp,x
    sta sched_debug_state_new

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

@resume_idle:
    ldx #IDLE_PID
    jsr proc_set_running

    lda #IDLE_PID
    ldx #<idle_loop
    ldy #>idle_loop
    jmp BIOS_CONTEXT_JUMP
.endproc

; ------------------------------------------------------------
; sched_yield
;
; Cooperative scheduler entry.
;
; Called from syscall/user context. The current task stack is
; saved as RTS-style state, not IRQ/RTI-style state.
;
; Monitor note:
;   irq_entry only sets monitor_pending. Actual monitor entry
;   happens here, outside IRQ context, after supervisor checks
;   subsystem locks.
; ------------------------------------------------------------

.proc sched_yield
    ; Cooperative scheduler entry must be non-preemptible from
    ; the first instruction. A timer IRQ racing with sys_yield
    ; must not enter sched_context_switch while sched_yield is
    ; setting up its own scheduler path.
    sei

    ; Cooperative monitor safe point.
    jsr supervisor_try_enter_pending
	
;debug
    lda #$04
    sta sched_debug_marker

    lda current_pid
    sta sched_debug_pid
;end debug

    ; Current yielding owner.
    ldy current_pid

;debug
    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state
;end debug

    ; --------------------------------------------------------
    ; PID 0 is not a normal task.
    ;
    ; Do not save proc_sp[0].
    ; Do not set proc_resume_mode[0] to RTS.
    ; Do not convert PID 0 to READY.
    ; --------------------------------------------------------

    cpy #IDLE_PID
    beq @wake

    ; Save current syscall/user stack pointer.
    tsx

    ; DEBUG-BEGIN: sched_yield save current owner SP
    ;
    ; sched_debug_old_pid   = PID whose stack is being saved
    ; sched_debug_state_old = SP observed at yield entry
    ;
    ; If a task stack leaks, this value will move downward over
    ; repeated yields before the scheduler stores it in proc_sp[].
    sty sched_debug_old_pid
    stx sched_debug_state_old
    ; DEBUG-END: sched_yield save current owner SP

    txa
    sta proc_sp,y

    ; This stack was saved from syscall/user context.
    lda #PROC_RESUME_RTS
    sta proc_resume_mode,y

    ; If caller is still RUNNING, make it READY.
    ; Blocking syscalls set PROC_BLOCKED before calling this,
    ; so they are left blocked.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake

    lda #$05
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    tya
    tax
    jsr proc_set_ready

    lda proc_state,x
    sta sched_debug_old_state

@wake:
    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

    jsr sched_pick_next
    ; DEBUG-BEGIN: sched_yield selected PID
    ;
    ; Captures the PID selected after wake processing.
    ; Useful when PID 3 is woken by console input.
    stx sched_debug_state_pid
    lda proc_state,x
    sta sched_debug_state_new
    ; DEBUG-END: sched_yield selected PID
; debug
    lda #$06
    sta sched_debug_marker

    txa
    sta sched_debug_pid
; end debug

    ; PID 0 is entered directly, not through proc_sp[0].
    cpx #IDLE_PID
    beq @resume_idle

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; Resume existing normal process.
    ;
    ; proc_set_running commits:
    ;   old current_pid -> READY, if applicable
    ;   selected X      -> RUNNING
    ;   current_pid     -> X
    ;
    ; It returns with X = current_pid.
    jsr proc_set_running

    ; DEBUG-BEGIN: sched_yield committed software PID
    lda #$61
    sta sched_debug_marker

    stx sched_debug_state_pid
    lda current_pid
    sta sched_debug_state_new
    ; DEBUG-END: sched_yield committed software PID

    stx sched_debug_state_pid
    lda proc_sp,x
    sta sched_debug_state_new

    lda proc_sp,x
    tax
    txs

    ; DEBUG-BEGIN: sched_yield loaded target stack
    lda #$62
    sta sched_debug_marker
    ; DEBUG-END: sched_yield loaded target stack

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

@resume_idle:
    ldx #IDLE_PID
    jsr proc_set_running

    lda #IDLE_PID
    ldx #<idle_loop
    ldy #>idle_loop
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
;   Restored process stack contains the RTS return address into
;   the syscall veneer.
;
; Notes:
;   sched_yield enters with IRQs disabled. Unlike RTI resume,
;   this path does not restore a saved processor status byte.
;   Re-enable IRQs before returning to the syscall veneer.
; ------------------------------------------------------------

.proc sched_resume_rts
    cli
    rts
.endproc
