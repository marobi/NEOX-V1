; ============================================================
; gate.asm
; NEOX - sleepable FIFO gate mechanism
; ca65
;
; Model:
;   - syscall-level serialization primitive
;   - FIFO wait queue per gate
;   - WAIT_LOCK + lock object id
;   - ownership belongs to a PID, not to the currently executing timeslice
;   - a gate may remain owned across scheduler preemption
;   - an explicit subsystem wait may retain a gate only when its protocol
;     requires stable ownership, such as the planned WAIT_RP transaction
;
; Provides generated concrete gates:
;   file_io_gate_*
;   proc_gate_*
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "signal.inc"

.export file_io_gate_init
.export file_io_gate_acquire
.export file_io_gate_release
.export file_io_gate_cancel_wait

.export proc_gate_init
.export proc_gate_acquire
.export proc_gate_release
.export proc_gate_cancel_wait

.import active_pid
.import proc_set_wait
.import proc_wake
.import sched_yield
.import proc_signal_pending
.import proc_flags

.import file_io_gate
.import file_io_gate_owner
.import file_io_gate_wait_head
.import file_io_gate_wait_tail
.import file_io_gate_next

.import proc_gate
.import proc_gate_owner
.import proc_gate_wait_head
.import proc_gate_wait_tail
.import proc_gate_next

.segment "KERN_TEXT"

; ------------------------------------------------------------
; gate_signal_checkpoint
;
; Purpose:
;   Force a scheduler pass immediately after the active process has released
;   its final sleepable gate when a default-action SIG_INT is pending.
;
; Policy:
;   - never acts on PID 0
;   - never acts while the active process still owns FILE_IO or PROC
;   - leaves PROC_FLAG_SIGINT_INTERRUPT processes alive; their pending SIG_INT
;     is consumed by the interruptible console-read path as EINTR
;   - does not apply the signal directly; scheduler signal handling remains
;     the sole owner of process termination
; ------------------------------------------------------------

.proc gate_signal_checkpoint
    ldx active_pid
    cpx #IDLE_PID
    beq @done

    cpx #MAX_PROCS
    bcs @done

    lda proc_signal_pending,x
    cmp #SIG_INT
    bne @done

    lda proc_flags,x
    and #PROC_FLAG_SIGINT_INTERRUPT
    bne @done

    lda file_io_gate_owner
    cmp active_pid
    beq @done

    lda proc_gate_owner
    cmp active_pid
    beq @done

    jsr sched_yield

@done:
    rts
.endproc

; ------------------------------------------------------------
; DEFINE_SLEEPABLE_GATE
;
; Parameters:
;   init_proc       concrete init routine name
;   acquire_proc    concrete acquire routine name
;   release_proc    concrete release routine name
;   enqueue_proc    private FIFO enqueue routine name
;   dequeue_proc    private FIFO dequeue routine name
;   gate_byte       0/1 ownership byte
;   owner_byte      debug owner PID, $FF when free
;   phase_byte      debug phase byte, gate-specific values
;   wait_head       FIFO head PID, $FF when empty
;   wait_tail       FIFO tail PID, $FF when empty
;   next_table      next[pid] FIFO links, $FF when not queued
;   lock_id         WAIT_LOCK object id
;   idle_phase      phase value written on init/release
;
; IRQ policy:
;   acquire/release protect gate metadata with php/sei/plp.
;   They do not disable scheduling after returning. A timer preemption does
;   not transfer ownership; owner_byte continues to identify the owning PID.
; ------------------------------------------------------------

.macro DEFINE_SLEEPABLE_GATE init_proc, acquire_proc, release_proc, enqueue_proc, dequeue_proc, gate_byte, owner_byte, wait_head, wait_tail, next_table, lock_id

.proc init_proc
    stz gate_byte
    lda #GATE_OWNER_NONE
    sta owner_byte
    sta wait_head
    sta wait_tail

    ldx #MAX_PROCS - 1
@clear_next:
    sta next_table,x
    dex
    bpl @clear_next

    rts
.endproc

; ------------------------------------------------------------
; enqueue_proc
;
; Input:
;   X = current PID
;
; IRQ policy:
;   Caller has IRQs disabled.
; ------------------------------------------------------------

.proc enqueue_proc
    ; Mark this PID as queue tail by default.
    lda #GATE_OWNER_NONE
    sta next_table,x

    lda wait_tail
    cmp #GATE_OWNER_NONE
    beq @empty

    ; Existing tail -> current PID.
    tay
    txa
    sta next_table,y
    stx wait_tail
    rts

@empty:
    stx wait_head
    stx wait_tail
    rts
.endproc

; ------------------------------------------------------------
; dequeue_proc
;
; Output:
;   C clear = X contains dequeued PID
;   C set   = FIFO empty
;
; IRQ policy:
;   Caller has IRQs disabled.
; ------------------------------------------------------------

.proc dequeue_proc
    ldx wait_head
    cpx #GATE_OWNER_NONE
    bne @have_pid

    sec
    rts

@have_pid:
    lda next_table,x
    sta wait_head
    cmp #GATE_OWNER_NONE
    bne @clear_link

    sta wait_tail

@clear_link:
    lda #GATE_OWNER_NONE
    sta next_table,x

    clc
    rts
.endproc

; ------------------------------------------------------------
; acquire_proc
;
; Behavior:
;   If the gate is free, acquire it and return.
;   If another PID owns it, enqueue active_pid FIFO, block on
;   WAIT_LOCK / lock_id, yield, and retry when woken.
;   If active_pid already owns it, trap.
;
; Return:
;   C set = acquired
; ------------------------------------------------------------

.proc acquire_proc
@retry:
    php
    sei

    lda #$01
    tsb gate_byte
    beq @acquired

    lda owner_byte
    cmp active_pid
    bne @wait_for_owner

    ; Do not hard-hang the system here.  A recursive acquire is
    ; still a kernel bug, but the monitor must remain usable.
    ; Return C clear so checked callers can fail/diagnose instead
    ; of spinning forever.  The original owner keeps the gate.
    plp
    clc
    rts

@wait_for_owner:
    ldx active_pid
    jsr enqueue_proc

    lda #WAIT_LOCK
    ldy #lock_id
    jsr proc_set_wait

    plp

    jsr sched_yield
    bra @retry

@acquired:
    ldx active_pid
    stx owner_byte

    plp
    sec
    rts
.endproc

; ------------------------------------------------------------
; release_proc
;
; Release the gate and wake exactly one FIFO waiter.
;
; Return:
;   C set
; ------------------------------------------------------------

.proc release_proc
    php
    sei

    lda owner_byte
    cmp active_pid
    beq @owner_ok

    ; Do not hard-hang on bad release either.  Leave the gate state
    ; untouched and return C clear for checked callers/monitor output.
    plp
    clc
    rts

@owner_ok:
    lda #GATE_OWNER_NONE
    sta owner_byte

    lda #$01
    trb gate_byte

    jsr dequeue_proc
    bcs @done

    ; X = FIFO waiter PID.
    jsr proc_wake

@done:
    plp

    ; A pending default SIG_INT may have been deferred while this process
    ; owned the gate. Once its final gate is released, enter the scheduler
    ; before user code can begin another syscall.
    jsr gate_signal_checkpoint

    sec
    rts
.endproc

.endmacro


; ------------------------------------------------------------
; DEFINE_GATE_CANCEL_WAIT
;
; Remove PID X from a gate FIFO without changing gate ownership.
; This is used when SIG_KILL converts a WAIT_LOCK process to ZOMBIE.
; IRQs are masked while the singly-linked FIFO is changed.
; ------------------------------------------------------------

.macro DEFINE_GATE_CANCEL_WAIT cancel_proc, wait_head, wait_tail, next_table

.proc cancel_proc
    php
    sei

    cpx wait_head
    bne @scan

    ; Removing the queue head.
    lda next_table,x
    sta wait_head
    cmp #GATE_OWNER_NONE
    bne @clear_link

    ; Removed the only queue entry.
    sta wait_tail
    bra @clear_link

@scan:
    ldy wait_head

@scan_next:
    cpy #GATE_OWNER_NONE
    beq @done

    txa
    cmp next_table,y
    beq @found

    lda next_table,y
    tay
    bra @scan_next

@found:
    ; Y = predecessor, X = entry being removed.
    lda next_table,x
    sta next_table,y

    cpx wait_tail
    bne @clear_link

    sty wait_tail

@clear_link:
    lda #GATE_OWNER_NONE
    sta next_table,x

@done:
    plp
    rts
.endproc

.endmacro

; ------------------------------------------------------------
; Concrete gate instances
; ------------------------------------------------------------

DEFINE_SLEEPABLE_GATE file_io_gate_init, file_io_gate_acquire, file_io_gate_release, file_io_gate_enqueue_current, file_io_gate_dequeue_one, file_io_gate, file_io_gate_owner, file_io_gate_wait_head, file_io_gate_wait_tail, file_io_gate_next, LOCK_ID_FILE_IO
DEFINE_GATE_CANCEL_WAIT file_io_gate_cancel_wait, file_io_gate_wait_head, file_io_gate_wait_tail, file_io_gate_next

DEFINE_SLEEPABLE_GATE proc_gate_init, proc_gate_acquire, proc_gate_release, proc_gate_enqueue_current, proc_gate_dequeue_one, proc_gate, proc_gate_owner, proc_gate_wait_head, proc_gate_wait_tail, proc_gate_next, LOCK_ID_PROC
DEFINE_GATE_CANCEL_WAIT proc_gate_cancel_wait, proc_gate_wait_head, proc_gate_wait_tail, proc_gate_next
