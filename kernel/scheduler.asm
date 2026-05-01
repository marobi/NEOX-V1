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

.include "process.inc"
.include "scheduler_defs.inc"
.include "mailbox.inc"
.include "../bios/bios.inc"

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
.export proc_set_blocked
.export proc_block_current
.export proc_wake
.export scheduler_wake_console_input

.import sched_lock_enter
.import sched_lock_leave

.import fd_init_process

.import current_pid
.import proc_state
.import proc_context
.import proc_sp
.import proc_entryL
.import proc_entryH
.import proc_flags
.import sched_lock
.import saved_task_pid
.import console_owner_pid
.import console_wait_pid
.import monitor_return_mode

.importzp sched_ptr

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
; proc_set_blocked
;
; Input:
;   X = pid
; ------------------------------------------------------------

.proc proc_set_blocked
    lda #PROC_BLOCKED
    jmp proc_set_state
.endproc

; ------------------------------------------------------------
; proc_block_current
;
; Purpose:
;   Mark current process BLOCKED.
;
; Notes:
;   This does NOT invoke sched_context_switch.
;   sched_context_switch is IRQ-only and expects an IRQ frame.
; ------------------------------------------------------------

.proc proc_block_current
    ldx current_pid
    jmp proc_set_blocked
.endproc

; ------------------------------------------------------------
; proc_wake
;
; Input:
;   X = pid
;
; Purpose:
;   Wake a blocked process by making it READY.
;
; Notes:
;   Caller is responsible for selecting the correct pid.
; ------------------------------------------------------------

.proc proc_wake
    jmp proc_set_ready
.endproc

; ------------------------------------------------------------
; scheduler_wake_console_input
;
; Purpose:
;   Wake the console owner when RP2350 reports input available.
;
; Source:
;   RP_CONSOLE_RDY is maintained by the RP2350:
;       0     = RP input FIFO empty
;       non-0 = one or more chars available
;
; Policy:
;   - Only normal task pids are woken here.
;   - PID 0 is monitor/supervisor and is not part of normal
;     round-robin scheduling.
;   - Only PROC_BLOCKED is changed to PROC_READY.
;
; Clobbers:
;   A, X
; ------------------------------------------------------------

.proc scheduler_wake_console_input
    lda RP_CONSOLE_RDY
    beq @done

    ldx console_wait_pid
    cpx #$FF
    beq @done

    cpx #FIRST_TASK_PID
    bcc @clear_wait

    cpx #MAX_PROCS
    bcs @clear_wait

    lda proc_state,x
    cmp #PROC_BLOCKED
    bne @clear_wait

    lda #$FF
    sta console_wait_pid
    jmp proc_wake

@clear_wait:
    lda #$FF
    sta console_wait_pid

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
    stz saved_task_pid
    stz monitor_return_mode

    lda #$FF
    sta console_owner_pid
    sta console_wait_pid

    ldx #$00

@clear:
    stz proc_state,x
    stz proc_context,x
    stz proc_sp,x
    stz proc_entryL,x
    stz proc_entryH,x
    stz proc_flags,x

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

    ; Initial process flags.
    lda #PROC_FLAG_NONE
    sta proc_flags,x

	; Initialise FD list
	;jsr fd_init_process
    
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
