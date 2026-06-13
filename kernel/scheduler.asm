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
.include "sched_lock.inc"

.export scheduler_init
.export scheduler_irq_tick
.export scheduler_set_current_context
.export scheduler_wake_one
.export sched_pick_next
.export sched_context_switch
.export sched_switch_context
.export sched_yield
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


.import fd_init_process
.import fd_close_process

.import active_pid
.import sched_cursor_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import proc_resume_mode
.import proc_parent_pid
.import proc_signal_pending

.import console_owner_pid

.import active_context

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

.import irq_restore

; ------------------------------------------------------------
.segment "KERN_BSS"

sched_wake_reason_tmp:
    .res 1

sched_wake_object_tmp:
    .res 1

; Scheduler-local scratch used only while sched_lock is held.
; It is not shared/RP-visible because it is an internal commit helper.
sched_selected_tmp:
    .res 1

; Handoff scratch used to publish active_pid/active_context only
; after IRQs are masked and immediately before BIOS context transfer.
sched_handoff_pid:
    .res 1

sched_handoff_context:
    .res 1

sched_handoff_sp:
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
;   Do not use debug fields as storage for correctness.
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
;   PROC_RUNNING is exclusive. On a single CPU, only active_pid
;   may be RUNNING.
;
;   This routine owns the transition:
;
;       old active_pid -> READY, if it was RUNNING
;       selected X      -> RUNNING
;       sched_cursor_pid -> X
;
; Important:
;   Call this before loading the selected process stack/context.
; ------------------------------------------------------------

.proc proc_set_running
    ; Enforce the single-RUNNING invariant directly.  Earlier code
    ; only demoted active_pid.  Once a stale RUNNING process exists,
    ; that leaves two RUNNING tasks visible and corrupts later picks.
    ; This routine is called only with sched_lock held.
    stx sched_selected_tmp

    ldx #IDLE_PID

@scan_running:
    cpx sched_selected_tmp
    beq @next_pid

    lda proc_state,x
    cmp #PROC_RUNNING
    bne @next_pid

    lda #PROC_READY
    jsr proc_set_state

@next_pid:
    inx
    cpx #MAX_PROCS
    bne @scan_running

    ldx sched_selected_tmp
    lda #PROC_RUNNING
    jsr proc_set_state

    stx sched_cursor_pid
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
;   sched_cursor_pid. This avoids always waking the lowest PID first.
;
; Example:
;   lda #WAIT_LOCK
;   ldy #LOCK_ID_FILE_IO
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

    ; Start scan after sched_cursor_pid for round-robin fairness.
    ldx sched_cursor_pid

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
    ldx active_pid
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
    ldx active_pid

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

    stz active_pid
    stz sched_cursor_pid
    stz sched_lock
    lda #DBG_OWNER_NONE
    sta sched_lock_owner
    stz sched_lock_phase
    stz sched_lock_depth
    stz sched_lock_underflow
	stz active_context


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
    ldx active_pid
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
;   - Bounded scan prevents infinite loop when sched_cursor_pid = 0.
;   - Uses sched_ptr as a 1-byte scan counter.
;   - Clobbers sched_ptr.
; ------------------------------------------------------------

.proc sched_pick_next
    ldx sched_cursor_pid

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

    stx sched_debug_state_pid
    sta sched_debug_state_old
	
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
    stx sched_debug_state_pid
    lda proc_state,x
    sta sched_debug_state_old

    lda #$EE
    sta sched_debug_marker

    ; A RUNNING normal process while no READY/NEW task was found is
    ; not a valid steady-state scheduler result, but halting here makes
    ; recovery impossible and hides the original boundary violation.
    ; Resume the RUNNING PID and keep the EE marker visible for ps.
    sec
    rts

@found:
    sec
    rts
.endproc

; ------------------------------------------------------------
; sched_switch_context
;
; Shared scheduler switch/resume path.
;
; Called by:
;   sched_context_switch
;   sched_yield
;
; Responsibilities:
;   - pick next runnable PID
;   - commit selected PID as RUNNING
;   - start PROC_NEW tasks
;   - resume existing tasks through the unified RTI path
;   - enter PID 0 idle loop if no normal task is runnable
;
; Notes:
;   This routine never returns.
; ------------------------------------------------------------

.proc sched_switch_context
    jsr sched_pick_next

    stx dbg_irq_selected_pid

    lda #DBG_MARK_PICK
    sta sched_debug_marker

    txa
    sta sched_debug_pid

    stx dbg_sched_selected_pid

    lda active_pid
    sta dbg_sched_current_pid

    ; PID 0 is entered directly, not through proc_sp[0].
    cpx #IDLE_PID
    bne @not_idle
    jmp resume_idle

@not_idle:
    lda proc_state,x
    cmp #PROC_NEW
    bne @resume_existing
    jmp start_new

@resume_existing:
    ; Commit selected PID as RUNNING.
    ;
    ; proc_set_running returns with:
    ;   X = selected PID / sched_cursor_pid
    jsr proc_set_running

    lda #DBG_MARK_SELECTED
    sta sched_debug_marker

    stx sched_debug_state_pid
    stx dbg_sched_loaded_pid
    stx dbg_sched_resume_pid

    lda sched_cursor_pid
    sta sched_debug_state_new

    lda proc_sp,x
    sta sched_debug_state_new
    sta dbg_sched_loaded_sp
    sta dbg_irq_loaded_sp

    lda dbg_sched_path
    cmp #DBG_PATH_IRQ
    bne @resume_mode_yield

    lda #DBG_MODE_IRQ_RTI
    bra @resume_mode_store

@resume_mode_yield:
    lda #DBG_MODE_YIELD_RTI

@resume_mode_store:
    sta dbg_sched_resume_mode

    lda proc_context,x
    sta dbg_sched_resume_context
    sta sched_handoff_context
    stx sched_handoff_pid

    ; The selected process stack is private to the selected context.
    ; Do not TXS or touch $0100..$01FF until after BIOS_CONTEXT_SWITCH.
    ; Carry the target SP in X; BIOS_CONTEXT_SWITCH preserves X.
    lda proc_sp,x
    sta sched_handoff_sp
    tax

    lda #DBG_MARK_STACK_LOAD
    sta sched_debug_marker

    ; Publish identity/context in the final masked handoff window while
    ; sched_lock is still held.  IRQ remains masked until the selected
    ; private stack is installed and sched_lock is released below.
    lda sched_handoff_pid
    sta active_pid
    lda sched_handoff_context
    sta active_context

    ; Switch private memory first.  This macro is stack-free and does
    ; not cross contexts with JSR/RTS.  X still contains target SP.
    lda sched_handoff_context
    BIOS_CONTEXT_SWITCH

    ; Now the selected process private stack is mapped.
    txs

    ; Force IRQ enabled in the selected task's saved P byte.
    ; Frame layout after TXS:
    ;   SP+1 = Y
    ;   SP+2 = X
    ;   SP+3 = A
    ;   SP+4 = P
    ;   SP+5 = PCL
    ;   SP+6 = PCH
    tsx
    lda $0104,x
    and #$fb
    sta $0104,x


    lda #DBG_MARK_RESUME_RTI
    sta sched_debug_marker

    ; Release as late as possible: context is switched and the selected
    ; private stack is installed, but the task frame has not yet been
    ; consumed.  sched_lock_leave uses the currently installed stack and restores it before return.
    jsr sched_lock_leave

    ply
    plx
    pla
    rti

start_new:
    jsr proc_set_running

    lda #DBG_MARK_RESUME_BOOT
    sta sched_debug_marker

    stx dbg_sched_resume_pid

    lda #DBG_MODE_BOOT
    sta dbg_sched_resume_mode

    lda proc_context,x
    sta dbg_sched_resume_context
    sta sched_handoff_context
    stx sched_handoff_pid

    ; First-run handoff: switch private context first, install a clean
    ; stack in that context, then release sched_lock and enter the
    ; bootstrap trampoline.  No JSR/RTS crosses the context switch.
    ;

    lda sched_handoff_pid
    sta active_pid
    lda sched_handoff_context
    sta active_context

    lda sched_handoff_context
    BIOS_CONTEXT_SWITCH

    ldx #$FF
    txs

    jsr sched_lock_leave

    jmp first_run_entry

resume_idle:
    ldx #IDLE_PID
    jsr proc_set_running

    lda #DBG_MARK_RESUME_BOOT
    sta sched_debug_marker

    lda #DBG_PID_NONE
    sta dbg_sched_loaded_pid
    stz dbg_sched_loaded_sp

    lda #DBG_MODE_BOOT
    sta dbg_sched_resume_mode

    lda #IDLE_PID
    sta dbg_sched_resume_pid
    sta dbg_sched_resume_context


    ; Idle runs in context 0.  Switch context first, install a clean
    ; supervisor/idle stack, then release sched_lock and jump directly.
    stz active_pid
    stz active_context

    lda #IDLE_PID
    BIOS_CONTEXT_SWITCH

    ldx #$FF
    txs

    jsr sched_lock_leave

    jmp idle_loop
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
;   - save current normal task state, if active_pid != 0
;   - account timer tick
;   - wake timer/console waiters
;   - jump to shared dispatch/resume path
;
; Notes:
;   This routine never returns directly.
; ------------------------------------------------------------

.proc sched_context_switch
    ; IRQ handler normally enters here only when sched_lock and
    ; subsystem locks were zero.  Still use the real try-lock result
    ; as the authority: if the guard is already held, this IRQ must
    ; resume the interrupted context unchanged.
    jsr sched_lock_try_enter
    bcc @irq_lock_acquired
    jmp @skip_locked

@irq_lock_acquired:
    lda #DBG_MARK_IRQ_ENTRY
    sta sched_debug_marker

    lda #DBG_PATH_IRQ
    sta dbg_sched_path

    lda active_pid
    sta sched_debug_pid
    sta dbg_sched_current_pid
    sta dbg_irq_current_pid

    inc dbg_irq_preempt_count

    lda #DBG_IRQ_ENTER_SWITCH
    sta dbg_irq_skip_reason

    ; Current interrupted owner.
    ldy active_pid

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

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

    sty sched_debug_old_pid
    stx sched_debug_state_old

    sty dbg_sched_saved_pid
    stx dbg_sched_saved_sp
    stx dbg_irq_saved_sp

    lda #DBG_MODE_IRQ_RTI
    sta dbg_sched_saved_mode


    txa
    sta proc_sp,y

    ; This stack was saved from IRQ context.
    lda #PROC_RESUME_RTI
    sta proc_resume_mode,y

    ; IRQ preemption: RUNNING -> READY.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    lda #DBG_MARK_IRQ_SAVE
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
    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

    jmp sched_switch_context

@skip_locked:
    lda #DBG_IRQ_SKIP_SCHED
    sta dbg_irq_skip_reason
    jmp irq_restore
.endproc

; ------------------------------------------------------------
; sched_yield
;
; Cooperative scheduler entry.
;
; Stack model:
;   The cooperative JSR return address is converted in-place into
;   the same IRQ-compatible extended RTI frame used by timer IRQ:
;
;       Y, X, A, P, PCL, PCH
;
;   The saved P byte has I cleared so the resumed task continues
;   with IRQs enabled.  The JSR return address is incremented by
;   one because RTS stores PC-1 while RTI expects the exact PC.
;
; Notes:
;   This routine never returns directly.
; ------------------------------------------------------------

.proc sched_yield
    ; --------------------------------------------------------
    ; Short atomic entry section.
    ; --------------------------------------------------------
    sei
    jsr sched_lock_try_enter
    bcc @yield_lock_acquired
    jmp @lock_busy

@yield_lock_acquired:
    lda #DBG_MARK_YIELD
    sta sched_debug_marker

    lda #DBG_PATH_YIELD
    sta dbg_sched_path

    lda active_pid
    sta sched_debug_pid
    sta dbg_sched_current_pid

    ; Current yielding owner.
    ldy active_pid

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    ; PID 0 is not a normal saved task.
    cpy #IDLE_PID
    beq @entry_done

    ; Convert current cooperative JSR continuation into the unified
    ; extended RTI frame expected by scheduler RTI resume / irq_restore:
    ;     Y, X, A, P, PCL, PCH
    ;
    ; Existing stack on entry:
    ;     PCL(JSR return - 1), PCH(JSR return - 1)
    ;
    ; Push order below transforms it into:
    ;     Y, X, A, P, PCL, PCH
    php
    pha
    phx
    phy

    ; Stack now points at saved Y.  Clear I in saved P and convert
    ; the JSR return address from PC-1 to exact RTI PC.
    tsx

    lda $0104,x
    and #$fb
    sta $0104,x

    inc $0105,x
    bne @pc_adjust_done
    inc $0106,x

@pc_adjust_done:
    sty sched_debug_old_pid
    stx sched_debug_state_old

    sty dbg_sched_saved_pid
    stx dbg_sched_saved_sp

    lda #DBG_MODE_YIELD_RTI
    sta dbg_sched_saved_mode


    txa
    sta proc_sp,y

    ; This stack is now an RTI-compatible frame.
    lda #PROC_FRAME_RTI
    sta proc_resume_mode,y

    ; If caller is still RUNNING, make it READY.
    ; Blocking syscalls set PROC_BLOCKED before calling this,
    ; so they are left blocked.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @entry_done

    lda #DBG_MARK_YIELD
    sta sched_debug_marker

    sty sched_debug_old_pid
    lda proc_state,y
    sta sched_debug_old_state

    tya
    tax
    jsr proc_set_ready

    lda proc_state,x
    sta sched_debug_old_state

@entry_done:
    ; --------------------------------------------------------
    ; Scheduler work remains IRQ-disabled.
    ;
    ; The current process stack now contains the saved RTI frame.
    ; Do not allow a nested IRQ/monitor entry to observe or save an
    ; intermediate scheduler stack depth as the process SP.
    ; --------------------------------------------------------

    jsr sched_update_console_focus
    jsr scheduler_wake_console_input
    jsr scheduler_wake_timers

    jmp sched_switch_context

@lock_busy:
    ; Cooperative yield while sched_lock is held is a scheduler
    ; recursion/invariant fault.  Returning would continue with a
    ; caller that expected sched_yield not to return, so stop here
    ; with an explicit marker instead of corrupting scheduler state.
    lda #DBG_MARK_SCHED_LOCK_OVERFLOW
    sta sched_debug_marker
    lda #DBG_SCHED_LOCK_NESTED
    sta sched_lock_phase
@halt:
    bra @halt
.endproc

; ------------------------------------------------------------
; first_run_entry
;
; Purpose:
;   Inline first-run bootstrap for PROC_NEW tasks.
;
; Notes:
;   This is a one-time bootstrap into a new MMU context, not a
;   process return-frame format.  Once the task yields or is
;   preempted, its continuation is saved only as an RTI frame.
; ------------------------------------------------------------

.proc first_run_entry
    ; Start with a clean private stack.
    ldx #$FF
    txs

    ; Resolve entry address into private zero-page sched_ptr.
    ldx active_pid
    lda proc_entryL,x
    sta sched_ptr
    lda proc_entryH,x
    sta sched_ptr+1

    lda proc_context,x
    sta active_context

    cld
    cli

    jmp (sched_ptr)
.endproc
