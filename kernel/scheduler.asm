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
.include "debug.inc"

.export scheduler_init
.export scheduler_irq_tick
.export scheduler_set_current_context
.export scheduler_wake_one
.export sched_pick_next
.export sched_context_switch
.export sched_yield
.export sched_resume_rts
.export sched_resume_idle
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

.importzp sched_ptr

.import wait_reason
.import wait_object

.import proc_apply_signal
.import proc_terminate

.import proc_exit_code

.import timer_init
.import scheduler_wake_timers

.import system_ticks_lo
.import system_ticks_hi

.import proc_ticks_lo
.import proc_ticks_hi

.import monitor_active

; ------------------------------------------------------------
.segment "KERN_BSS"

sched_wake_reason_tmp:
    .res 1

sched_wake_object_tmp:
    .res 1
	
.segment "KERN_TEXT"

; ------------------------------------------------------------
; scheduler_tick
;
; Purpose:
;   Increment global 16-bit scheduler tick counter.
;
; Called from:
;   timer IRQ path, once per scheduler tick.
; ------------------------------------------------------------

.proc scheduler_tick
    inc system_ticks_lo
    bne @done

    inc system_ticks_hi

@done:
    rts
.endproc

; ------------------------------------------------------------
; scheduler_irq_tick
;
; Purpose:
;   Account one hardware timer IRQ.
;
; Policy:
;   This must run for every timer IRQ, even when the kernel is
;   not at a safe preemption point.
;
; Notes:
;   This only accounts time. It does not select or switch tasks.
; ------------------------------------------------------------

.proc scheduler_irq_tick
    jsr sched_account_tick
    jmp scheduler_tick
.endproc

; ------------------------------------------------------------
; proc_set_state
;
; Input:
;   X = PID
;   A = new state
;
; Purpose:
;   Set proc_state[X] and record both legacy and explicit debug
;   state-transition fields.
;
; Important:
;   Do not use debug fields as temporary storage for correctness.
;   The real new state is preserved on the stack.
; ------------------------------------------------------------

.proc proc_set_state
    pha

    stx sched_debug_state_pid
    stx dbg_proc_state_pid

    lda proc_state,x
    sta sched_debug_state_old
    sta dbg_proc_state_old

    pla
    sta sched_debug_state_new
    sta dbg_proc_state_new
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

    ; Demote old current_pid if it is currently RUNNING.
    ; PID 0 is the idle task, not an empty slot, so it becomes
    ; READY when another process is selected.
    ldx current_pid

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
; scheduler_wake_one
;
; Input:
;   A = wait reason
;   Y = wait object
;
; Output:
;   C clear = one matching process was woken
;   C set   = no matching waiter found
;
; Purpose:
;   Wake one blocked process waiting on a specific
;   wait_reason / wait_object pair.
;
; Policy:
;   Scans normal task PIDs in round-robin order, starting after
;   current_pid. This avoids always waking the lowest PID first.
;
; Example:
;   lda #WAIT_KSYS_IO
;   ldy #$00
;   jsr scheduler_wake_one
;
; Notes:
;   This helper does not disable IRQs by itself.
;   Callers that need release+wake atomicity must already protect
;   the surrounding sequence, for example:
;
;       php
;       sei
;       release resource
;       jsr scheduler_wake_one
;       plp
; ------------------------------------------------------------

.proc scheduler_wake_one
    sta sched_wake_reason_tmp
    sty sched_wake_object_tmp

    ; Start scan after current_pid for round-robin fairness.
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
    cmp #PROC_BLOCKED
    bne @next

    lda wait_reason,x
    cmp sched_wake_reason_tmp
    bne @next

    lda wait_object,x
    cmp sched_wake_object_tmp
    bne @next

    jsr proc_wake
    clc
    rts

@next:
    dec sched_ptr
    beq @none

    inx
    cpx #MAX_PROCS
    bne @check

    ldx #FIRST_TASK_PID
    bra @check

@none:
    sec
    rts
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
    jsr proc_set_state

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
	
    stz system_ticks_lo
    stz system_ticks_hi

    stz current_pid
    stz sched_lock

	stz monitor_active
	
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
	stz proc_signal_pending,x
	
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
; sched_dispatch_next
;
; Shared scheduler dispatch/resume path.
;
; Called by:
;   sched_context_switch
;   sched_yield
;
; Responsibilities:
;   - pick next runnable PID
;   - commit selected PID as RUNNING
;   - start PROC_NEW tasks
;   - resume existing tasks through RTI or RTS path
;   - enter PID 0 idle loop if no normal task is runnable
;
; Notes:
;   This routine never returns.
; ------------------------------------------------------------

.proc sched_dispatch_next
    jsr sched_pick_next

    ; DEBUG-BEGIN: scheduler selected PID snapshot
    lda #DBG_MARK_PICK
    sta sched_debug_marker

    txa
    sta sched_debug_pid

    stx dbg_sched_selected_pid

    lda current_pid
    sta dbg_sched_current_pid
    ; DEBUG-END: scheduler selected PID snapshot

    ; PID 0 is entered directly, not through proc_sp[0].
    cpx #IDLE_PID
    bne @not_idle
    jmp @resume_idle

@not_idle:
    lda proc_state,x
    cmp #PROC_NEW
    bne @resume_existing
    jmp @start_new

@resume_existing:
    ; Commit selected PID as RUNNING.
    ;
    ; proc_set_running returns with:
    ;   X = current_pid
    jsr proc_set_running

    ; DEBUG-BEGIN: scheduler committed selected PID
    lda #DBG_MARK_SELECTED
    sta sched_debug_marker

    stx sched_debug_state_pid
    stx dbg_sched_loaded_pid

    lda current_pid
    sta sched_debug_state_new
    ; DEBUG-END: scheduler committed selected PID

    ; DEBUG-BEGIN: scheduler load snapshot
    lda proc_sp,x
    sta sched_debug_state_new
    sta dbg_sched_loaded_sp

    lda proc_resume_mode,x
    sta dbg_sched_resume_mode
    ; DEBUG-END: scheduler load snapshot

    ; Load selected process stack.
    lda proc_sp,x
    tax
    txs

    ; DEBUG-BEGIN: scheduler stack loaded
    lda #DBG_MARK_STACK_LOAD
    sta sched_debug_marker
    ; DEBUG-END: scheduler stack loaded

    ; X currently contains SP, not PID.
    ldx current_pid

    lda proc_resume_mode,x
    cmp #PROC_RESUME_RTS
    beq @resume_rts

@resume_rti:
    ; DEBUG-BEGIN: force IRQ enabled in RTI resume frame
    tsx
    lda $0104,x
    and #$fb
    sta $0104,x
    ; DEBUG-END: force IRQ enabled in RTI resume frame

    ldx current_pid

    ; DEBUG-BEGIN: scheduler RTI resume snapshot
    lda #DBG_MARK_RESUME_RTI
    sta sched_debug_marker

    stx dbg_sched_resume_pid

    lda #DBG_MODE_IRQ_RTI
    sta dbg_sched_resume_mode

    lda proc_context,x
    sta dbg_sched_resume_context
    ; DEBUG-END: scheduler RTI resume snapshot

    ; Scheduler handoff is complete. RTI restores task P.
    jsr sched_lock_leave

    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@resume_rts:
    ; DEBUG-BEGIN: scheduler RTS resume snapshot
    lda #DBG_MARK_RESUME_RTS
    sta sched_debug_marker

    stx dbg_sched_resume_pid

    lda #DBG_MODE_YIELD_RTS
    sta dbg_sched_resume_mode

    lda proc_context,x
    sta dbg_sched_resume_context
    ; DEBUG-END: scheduler RTS resume snapshot

    lda proc_context,x
    ldx #.lobyte(sched_resume_rts)
    ldy #.hibyte(sched_resume_rts)
    jmp BIOS_CONTEXT_JUMP

@start_new:
    jsr proc_set_running

    ; DEBUG-BEGIN: scheduler first-run snapshot
    lda #DBG_MARK_RESUME_RTS
    sta sched_debug_marker

    stx dbg_sched_resume_pid

    lda #DBG_MODE_YIELD_RTS
    sta dbg_sched_resume_mode

    lda proc_context,x
    sta dbg_sched_resume_context
    ; DEBUG-END: scheduler first-run snapshot

    lda proc_context,x
    ldx #.lobyte(first_run_entry)
    ldy #.hibyte(first_run_entry)
    jmp BIOS_CONTEXT_JUMP

@resume_idle:
    ldx #IDLE_PID
    jsr proc_set_running

    ; DEBUG-BEGIN: scheduler idle resume snapshot
    lda #DBG_MARK_RESUME_RTS
    sta sched_debug_marker

    lda #DBG_PID_NONE
    sta dbg_sched_loaded_pid
    stz dbg_sched_loaded_sp
    stz dbg_sched_resume_mode

    lda #IDLE_PID
    sta dbg_sched_resume_pid
    sta dbg_sched_resume_context

    lda #DBG_MODE_YIELD_RTS
    sta dbg_sched_resume_mode
    ; DEBUG-END: scheduler idle resume snapshot

	lda #IDLE_PID
	ldx #.lobyte(sched_resume_idle)
	ldy #.hibyte(sched_resume_idle)
	jmp BIOS_CONTEXT_JUMP
.endproc


; ------------------------------------------------------------
; sched_context_switch
;
; IRQ/timer scheduler entry.
;
; Called from IRQ context. The current task stack is saved as
; RTI-style state because the interrupted stack contains an IRQ
; return frame.
;
; Responsibilities:
;   - save current normal task state, if current_pid != 0
;   - account timer tick
;   - wake timer/console waiters
;   - jump to shared dispatch/resume path
;
; Notes:
;   This routine never returns directly.
; ------------------------------------------------------------

.proc sched_context_switch
    ; IRQ handler only enters here when sched_lock and subsystem
    ; locks were zero. From this point until final task handoff,
    ; block nested preemptive scheduling.
    jsr sched_lock_enter

    ; DEBUG-BEGIN: scheduler IRQ entry
    lda #DBG_MARK_IRQ_ENTRY
    sta sched_debug_marker

    lda #DBG_PATH_IRQ
    sta dbg_sched_path

    lda current_pid
    sta sched_debug_pid
    sta dbg_sched_current_pid
    ; DEBUG-END: scheduler IRQ entry

    ; Current interrupted owner.
    ldy current_pid

    ; DEBUG-BEGIN: scheduler IRQ current owner state
    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state
    ; DEBUG-END: scheduler IRQ current owner state

    ; --------------------------------------------------------
    ; PID 0 is not a normal saved task.
    ;
    ; Do not save proc_sp[0].
    ; Do not set proc_resume_mode[0].
    ; Do not convert PID 0 to READY.
    ; --------------------------------------------------------

    cpy #IDLE_PID
    beq @wake_events

    ; Save interrupted SP for normal task.
    tsx

    ; DEBUG-BEGIN: scheduler IRQ save snapshot
    sty sched_debug_old_pid
    stx sched_debug_state_old

    sty dbg_sched_saved_pid
    stx dbg_sched_saved_sp

    lda #DBG_MODE_IRQ_RTI
    sta dbg_sched_saved_mode
    ; DEBUG-END: scheduler IRQ save snapshot

    txa
    sta proc_sp,y

    ; This stack was saved from IRQ context.
    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    ; IRQ preemption: RUNNING -> READY.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    ; DEBUG-BEGIN: scheduler IRQ running-to-ready
    lda #DBG_MARK_IRQ_SAVE
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state
    ; DEBUG-END: scheduler IRQ running-to-ready

    tya
    tax
    jsr proc_set_ready

    ; DEBUG-BEGIN: scheduler IRQ state after ready
    lda proc_state,x
    sta sched_debug_old_state
    ; DEBUG-END: scheduler IRQ state after ready

@wake_events:
    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

    jmp sched_dispatch_next
.endproc

; ------------------------------------------------------------
; sched_yield
;
; Cooperative scheduler entry.
;
; IRQ policy:
;   IRQs are disabled only while the current task stack/state is
;   captured and during the final handoff into sched_dispatch_next.
;
;   sched_lock is the longer preemption gate. While sched_lock != 0,
;   timer IRQs may still enter and account ticks through
;   scheduler_irq_tick, but irq.asm must not enter
;   sched_context_switch.
;
; Stack model:
;   Current task is saved as RTS-style state.
;
; Notes:
;   This routine never returns directly.
; ------------------------------------------------------------

.proc sched_yield
    ; --------------------------------------------------------
    ; Short atomic entry section.
    ;
    ; Protect current_pid/proc_sp/proc_resume_mode/proc_state
    ; capture from timer preemption.
    ; --------------------------------------------------------
    sei
    jsr sched_lock_enter

    ; DEBUG-BEGIN: scheduler yield entry
    lda #DBG_MARK_YIELD
    sta sched_debug_marker

    lda #DBG_PATH_YIELD
    sta dbg_sched_path

    lda current_pid
    sta sched_debug_pid
    sta dbg_sched_current_pid
    ; DEBUG-END: scheduler yield entry

    ; Current yielding owner.
    ldy current_pid

    ; DEBUG-BEGIN: scheduler yield current owner state
    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state
    ; DEBUG-END: scheduler yield current owner state

    ; PID 0 is not a normal saved task.
    cpy #IDLE_PID
    beq @entry_done

    ; Save current syscall/user stack pointer.
    tsx

    ; DEBUG-BEGIN: scheduler yield save snapshot
    sty sched_debug_old_pid
    stx sched_debug_state_old

    sty dbg_sched_saved_pid
    stx dbg_sched_saved_sp

    lda #DBG_MODE_YIELD_RTS
    sta dbg_sched_saved_mode
    ; DEBUG-END: scheduler yield save snapshot

    txa
    sta proc_sp,y

    ; This stack was saved from syscall/yield context.
    lda #PROC_RESUME_RTS
    sta proc_resume_mode,y

    ; If caller is still RUNNING, make it READY.
    ; Blocking syscalls set PROC_BLOCKED before calling this,
    ; so they are left blocked.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @entry_done

    ; DEBUG-BEGIN: scheduler yield running-to-ready
    lda #DBG_MARK_YIELD
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state
    ; DEBUG-END: scheduler yield running-to-ready

    tya
    tax
    jsr proc_set_ready

    ; DEBUG-BEGIN: scheduler yield state after ready
    lda proc_state,x
    sta sched_debug_old_state
    ; DEBUG-END: scheduler yield state after ready

@entry_done:
    ; --------------------------------------------------------
    ; Long scheduler work with IRQs enabled.
    ;
    ; Timer IRQs are accepted here and counted by
    ; scheduler_irq_tick. Because sched_lock != 0, irq.asm must
    ; return from IRQ without entering sched_context_switch.
    ; --------------------------------------------------------
    cli

    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

    sei
    jmp sched_dispatch_next
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

    ; Scheduler handoff is complete in target context.
    jsr sched_lock_leave
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
    ; Scheduler handoff is complete in target context.
    jsr sched_lock_leave
    cli
    rts
.endproc

;
;
;
.proc sched_resume_idle
    ; Scheduler handoff is complete in idle context.
    jsr sched_lock_leave
    cli
    jmp idle_loop
.endproc
