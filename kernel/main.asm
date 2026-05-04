; ============================================================
; main.asm
; NEOX - kernel entry point
;
; Purpose:
;   Main kernel bootstrap entered from BIOS.
;
; Architecture:
;   - BIOS owns RESET and the hardware vectors
;   - BIOS transfers control here after machine-level startup
;   - Context 0 is the supervisor/debug context
;   - Runnable tasks live in contexts 1..N
;
; Boot policy:
;   - Initialize shared RP2350-side communication state
;   - Initialize scheduler tables
;   - Associate current execution with supervisor context 0
;   - Create initial runnable tasks
;   - Stay in supervisor context and wait for first IRQ
;
; Scheduling model:
;   - First task dispatch happens on the first timer IRQ
;   - kernel_main does NOT jump directly into scheduler switch code
;   - sched_context_switch is entered only from irq_entry
; ============================================================

.setcpu "65C02"

.include "process.inc"
.include "scheduler_defs.inc"
.include "mailbox.inc"

.export kernel_main
.export set_brk_vector

.import kernel_version

.import irq_entry
.import brk_vector
.import irq_restore

.import scheduler_init
.import scheduler_set_current_context

.import fd_init_tables
.import fd_init_process

.import tasks_init

.import current_pid
.import console_owner_pid
.import proc_state

.import rp_lock

.segment "KERN_TEXT"

; ------------------------------------------------------------
; kernel_main
;
; Purpose:
;   Perform kernel-side bootstrap after BIOS transfers control.
;
; Inputs:
;   None explicitly.
;
; Outputs:
;   Does not return.
;
; Clobbers:
;   A, X
;
; Notes:
;   - Remains in supervisor context 0 after setup.
;   - Normal task execution begins only when timer IRQ arrives.
;   - Shared communication/mailbox state is initialized here.
; ------------------------------------------------------------

.proc kernel_main
    ; --------------------------------------------------------
    ; Basic CPU setup for supervisor entry.
    ; --------------------------------------------------------
    sei                     ; no interrupts during bootstrap
    cld
    ldx #$FF
    txs                     ; initialize supervisor stack
	
	lda #<irq_restore
	sta brk_vector
	lda #>irq_restore
	sta brk_vector+1
	
	jsr rp_init
	
    ; --------------------------------------------------------
	; set the version of the kernel
    ; --------------------------------------------------------
	lda #$01				; minor
	sta kernel_version
	Lda #$02				; major
	sta kernel_version+1
	
    ; --------------------------------------------------------
    ; Initialize scheduler tables and mark current execution as
    ; supervisor context 0.
    ; --------------------------------------------------------
    jsr scheduler_init
	    
    ; --------------------------------------------------------
    ; Initialize fd table/objects
    ; --------------------------------------------------------
	jsr fd_init_tables

	ldx #IDLE_PID
	jsr fd_init_process

	; --------------------------------------------------------
    ; Create initial runnable tasks.
    ; tasks_init is expected to create processes in contexts
    ; 1..N and mark them runnable (typically PROC_NEW).
    ; --------------------------------------------------------
    jsr tasks_init

    ; --------------------------------------------------------
    ; Mark IDLE_PID execution 
    ; --------------------------------------------------------
    lda #0
    sta current_pid
	
	lda #$FF
    sta console_owner_pid

	ldx #IDLE_PID
    lda #PROC_RUNNING
    sta proc_state,x

    lda #$00
    jsr scheduler_set_current_context

	; enable interrupts
	cli
	
    ; --------------------------------------------------------
    ; Supervisor idle loop.
    ;
    ; Context 0 remains active until the first scheduler timer
    ; IRQ arrives. irq_entry will then save the current context
    ; and dispatch the first runnable task.
    ;
    ; For now this is a tight loop. Later this could become:
    ;   - a monitor wait loop
    ;   - a low-power wait
    ;   - a supervisor command loop
    ; --------------------------------------------------------
@idle:
    bra @idle
.endproc

.proc rp_init
    ; --------------------------------------------------------
    ; Initialize shared RP2350 communication state.
    ;
    ; These registers/state bytes are shared resources and
    ; must start from a known idle state before tasks begin.
    ; --------------------------------------------------------
    stz rp_lock

    stz RP_ARG0L
    stz RP_ARG0H
    stz RP_ARG1L
    stz RP_ARG1H
    stz RP_ARG2L
    stz RP_ARG2H
    stz RP_RES0L
    stz RP_RES0H
    stz RP_ERR
    stz RP_FLAGS
    stz RP_STATE
    stz RP_STATUS

    stz RP_DOORBELL
	rts
.endproc

;
;  provide a vector for BREAK processing
;
.proc set_brk_vector
	sta brk_vector
	stx brk_vector+1
	rts
.endproc