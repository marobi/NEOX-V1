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
.include "klog.inc"
.include "version.inc"

.export kernel_main
.export set_brk_vector

.import kernel_version

.import irq_entry
.import brk_vector
.import irq_restore


.import scheduler_init
.import scheduler_set_current_context
.import ctx_init_table

.import fd_init_tables
.import fd_init_process

.import pipe_init_tables

.import tasks_init
.import idle_loop

.import active_pid
.import sched_cursor_pid
.import console_owner_pid
.import proc_state

.import rp_lock

.import ksys_io_init

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

    KLOG_CLEAR
    KLOG_BOOT msg_klog_start
	
	lda #<irq_restore
	sta brk_vector
	lda #>irq_restore
	sta brk_vector+1
	
	jsr rp_init
    KLOG_OK msg_klog_rp_init
	
    ; --------------------------------------------------------
	; set the version of the kernel
    ; --------------------------------------------------------
	lda #$09				; minor: pipe endpoint flags folded into pipe_state
	sta kernel_version
	Lda #$02				; major
	sta kernel_version+1
    KLOG_OK msg_klog_version
	
	
    ; --------------------------------------------------------
    ; Initialize scheduler tables and mark current execution as
    ; supervisor context 0.
    ; --------------------------------------------------------
    jsr scheduler_init
    KLOG_OK msg_klog_scheduler_init

    ; --------------------------------------------------------
    ; Initialize kernel-owned context slot state.
    ; RP/boot has already created and preloaded the physical
    ; MMU contexts; NEOX only owns allocation status.
    ; --------------------------------------------------------
    jsr ctx_init_table
    KLOG_OK msg_klog_ctx_init
	    
    ; --------------------------------------------------------
    ; Initialize ksys/fd/pipe
    ; --------------------------------------------------------
	jsr ksys_io_init
    KLOG_OK msg_klog_ksys_io_init
	jsr fd_init_tables
    KLOG_OK msg_klog_fd_init
	jsr pipe_init_tables
    KLOG_OK msg_klog_pipe_init

	ldx #IDLE_PID
	jsr fd_init_process
    KLOG_OK msg_klog_idle_process_init

	; --------------------------------------------------------
    ; Create initial runnable tasks.
    ; tasks_init creates processes from the user entry table.
    ; proc_create allocates both PID and preloaded context.
    ; --------------------------------------------------------
    jsr tasks_init
    KLOG_OK msg_klog_tasks_init

    ; --------------------------------------------------------
    ; Mark IDLE_PID execution 
    ; --------------------------------------------------------
    ldx #IDLE_PID
    stx active_pid
    stx sched_cursor_pid
	
    lda #PROC_RUNNING
    sta proc_state,x

	lda #$FF
    sta console_owner_pid

    lda #$00
    jsr scheduler_set_current_context

    KLOG_OK msg_klog_ready

	; enable interrupts
	cli
	
	jmp idle_loop
.endproc

msg_klog_start:
    .byte "NEOX kernel "
    NEOX_VERSION_BYTES
    .byte " start", $00
msg_klog_rp_init:
    .byte "rp init", $00
msg_klog_version:
    .byte "kernel interface version set", $00
msg_klog_scheduler_init:
    .byte "scheduler init", $00
msg_klog_ctx_init:
    .byte "context table init", $00
msg_klog_ksys_io_init:
    .byte "ksys io init", $00
msg_klog_fd_init:
    .byte "fd init", $00
msg_klog_pipe_init:
    .byte "pipe init", $00
msg_klog_idle_process_init:
    .byte "idle process init", $00
msg_klog_tasks_init:
    .byte "tasks init", $00
msg_klog_ready:
    .byte "kernel boot done", $00

.proc rp_init
    ; --------------------------------------------------------
    ; Initialize shared RP2350 communication state.
    ;
    ; These registers/state bytes are shared resources and
    ; must start from a known idle state before tasks begin.
    ; --------------------------------------------------------
    stz rp_lock

	ldx #0
@rp_clear:
    stz RP_GROUP,x
	inx
	cpx #$14
	bne @rp_clear
	
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
