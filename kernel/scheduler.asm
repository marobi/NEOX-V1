; ============================================================
; scheduler.asm
; NEOX - timer-driven scheduler core
;
; Purpose:
;   Implements process scheduling and context switching.
;
; Architecture:
;   - pid 0 = monitor/supervisor process descriptor
;   - pid 0 is NOT selected by normal round-robin scheduling
;   - existing tasks resume through BIOS_CONTEXT_RTI
;   - PROC_NEW tasks are started directly inside this file
;   - process state is stored in array-based process table
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
.import monitor_pid
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

    ldx console_owner_pid
    cpx #FIRST_TASK_PID
    bcc @done

    cpx #MAX_PROCS
    bcs @done

    lda proc_state,x
    cmp #PROC_BLOCKED
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
    stz current_pid
    stz sched_lock
    stz console_owner_pid
    stz saved_task_pid
    stz monitor_return_mode
    stz monitor_pid

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
; has_monitor_context
;
; Return:
;   C set   = context 0 already owned by a live process
;   C clear = free
; ------------------------------------------------------------

.proc has_monitor_context
    ldx #$00

@scan:
    lda proc_state,x
    beq @next

    lda proc_context,x
    beq @found

@next:
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

    ldy #proc_create_args::context
    lda (sched_ptr),y
    beq @alloc_monitor

    jsr find_free_pid
    bcc @fail
    bra @fill

@alloc_monitor:
    lda proc_state+0
    bne @fail
    ldx #$00

@fill:
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
    cpx #$00
    bne @store_flags

    lda #PROC_FLAG_MONITOR
    stx monitor_pid

@store_flags:
    sta proc_flags,x

    ; Publish process as NEW only after all other fields exist.
    lda #PROC_NEW
    jsr proc_set_state

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
    beq @none

    inx
    cpx #MAX_PROCS
    bne @check

    ldx #FIRST_TASK_PID
    bra @check

@found:
    sec
    rts

@none:
    clc
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
    ; Save interrupted SP using Y as pid index.
    ldy current_pid
    tsx
    txa
    sta proc_sp,y

    ; Convert current RUNNING task back to READY.
    ; Do not modify pid 0.
    ; Do not turn BLOCKED back into READY here.
    cpy #$00
    beq @wake_events

    lda proc_state,y
    cmp #PROC_RUNNING
    bne @wake_events

    tya
    tax
    jsr proc_set_ready

@wake_events:
    ; External readiness events may make blocked tasks runnable.
    jsr scheduler_wake_console_input

@pick:
    jsr sched_pick_next
    bcc @resume_current

    ; X = selected pid.
    stx current_pid

    lda proc_state,x
    cmp #PROC_NEW
    beq @start_new

    ; --------------------------------------------------------
    ; Resume existing task.
    ; --------------------------------------------------------
    jsr proc_set_running

    ; Restore target SP before terminal context transfer.
    lda proc_sp,x
    tax
    txs

    ; X was clobbered by TAX above, reload pid.
    ldx current_pid
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@start_new:
    ; --------------------------------------------------------
    ; Start a new task for the first time.
    ; --------------------------------------------------------
    jsr proc_set_running

    lda proc_context,x
    ldx #<first_run_entry
    ldy #>first_run_entry
    jmp BIOS_CONTEXT_JUMP

@resume_current:
    ; --------------------------------------------------------
    ; No runnable task found.
    ;
    ; If current process is BLOCKED, it must not be resumed.
    ; In a healthy configuration there should normally be at
    ; least one runnable task. If none exists and current is not
    ; runnable, fall back to pid 0 context.
    ; --------------------------------------------------------
    ldx current_pid

    lda proc_state,x
    cmp #PROC_RUNNING
    beq @resume_existing_current

    cmp #PROC_READY
    beq @resume_ready_current

    ; Current task is not runnable. Fall back to monitor pid 0.
    ldx #$00
    stx current_pid
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI

@resume_ready_current:
    jsr proc_set_running

@resume_existing_current:
    lda proc_sp,x
    tax
    txs

    ldx current_pid
    lda proc_context,x
    jmp BIOS_CONTEXT_RTI
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
