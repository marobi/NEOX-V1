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
.import sched_lock
.import console_owner_pid
.import monitor_return_mode

.importzp sched_ptr

.import wait_reason
.import wait_object

.import proc_exit_code

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
; Input:
;   X = pid
;   A = wait reason
;   Y = wait object
;
; Purpose:
;   Mark a process as blocked on a specific wait reason/object.
;
; Notes:
;   This is the generic replacement for device-specific wait
;   variables such as console_wait_pid.
; ------------------------------------------------------------

.proc proc_set_wait
    sta wait_reason,x
    tya
    sta wait_object,x

    lda #PROC_BLOCKED
    jmp proc_set_state
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
    ; Resolve exiting PID.
    ldx current_pid

    ; Release all process-owned file descriptors.
    jsr fd_close_process

    ; Clear generic wait metadata.
    jsr proc_clear_wait

    ; Mark process slot unused.
    lda #PROC_EMPTY
    jmp proc_set_state
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
    beq @set_focus

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
; Purpose:
;   Wake processes blocked on console input when RP reports that
;   keyboard data is available.
;
; Model:
;   A process is considered console-blocked when:
;
;       proc_state[pid]  == PROC_BLOCKED
;       wait_reason[pid] == WAIT_CONSOLE
;
; Notes:
;   This currently wakes the first matching process.
;   With the console ownership invariant, only the owner should
;   be waiting on console input anyway.
; ------------------------------------------------------------

.proc scheduler_wake_console_input
    ; No input ready → nothing to wake.
    lda RP_CONSOLE_RDY
    beq @done

    ; Scan user task PIDs only.
    ldx #FIRST_TASK_PID

@scan:
    cpx #MAX_PROCS
    bcs @done

    ; Only blocked processes can be woken.
    lda proc_state,x
    cmp #PROC_BLOCKED
    bne @next

    ; Only wake console waiters here.
    lda wait_reason,x
    cmp #WAIT_CONSOLE
    bne @next

    ; Clear wait state before making process READY.
    ; The wake reason is now satisfied.
    jsr proc_clear_wait

    ; Wake this process.
    jsr proc_wake

    ; Current console model has only one console waiter.
    rts

@next:
    inx
    bra @scan

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
;   Perform timer-driven context switching.
;
; Entry conditions:
;   - entered from irq_entry
;   - stack contains hardware IRQ frame + saved A/X/Y
;
; Behavior:
;   - save current SP
;   - wake blocked console owner if RP input is ready
;   - mark current RUNNING task READY, except pid 0
;   - pick next runnable pid
;   - existing task -> BIOS_CONTEXT_RTI
;   - new task      -> BIOS_CONTEXT_JUMP into inline bootstrap
;
; Important:
;   A task that has changed itself to PROC_BLOCKED must remain
;   blocked. Therefore this routine only converts RUNNING to
;   READY. It must not blindly write READY to the current pid.
; ------------------------------------------------------------

.proc sched_context_switch
    ; Save interrupted SP.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Convert only RUNNING -> READY.
    ; This applies to PID 0 as well, so only one PID is RUNNING.
    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    tya
    tax
    jsr proc_set_ready
	
@wake_events:
	jsr sched_update_console_focus
    jsr scheduler_wake_console_input

@pick:
    jsr sched_pick_next

    ; X = selected PID, including possible IDLE_PID fallback.
    stx current_pid

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; Resume existing task/idle.
    jsr proc_set_running

    lda proc_sp,x
    tax
    txs

    ldx current_pid
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

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

    ; First-run path does not restore P via RTI.
    cli

    ; Resolve entry address into private zero-page sched_ptr.
    ldx current_pid
    lda proc_entryL,x
    sta sched_ptr
    lda proc_entryH,x
    sta sched_ptr+1

    jmp (sched_ptr)
.endproc

; ------------------------------------------------------------
; sched_yield
;
; Purpose:
;   Placeholder for cooperative yield.
; ------------------------------------------------------------

.proc sched_yield
    rts
.endproc
