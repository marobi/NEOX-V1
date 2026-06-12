; ============================================================
; gate.asm
; NEOX - sleepable FIFO gate mechanism
; ca65
;
; Model:
;   - syscall-level serialization primitive
;   - FIFO wait queue per gate
;   - WAIT_LOCK + lock object id
;   - no gate may be held across sched_yield
;
; Provides generated concrete gates:
;   file_io_gate_*
;   proc_gate_*
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "process.inc"
.include "debug.inc"

.export file_io_gate_init
.export file_io_gate_acquire
.export file_io_gate_release

.export proc_gate_init
.export proc_gate_acquire
.export proc_gate_release

.import active_pid
.import proc_set_wait
.import proc_wake
.import sched_yield

.import file_io_gate
.import file_io_gate_owner
.import file_io_gate_phase
.import file_io_gate_wait_head
.import file_io_gate_wait_tail
.import file_io_gate_next

.import proc_gate
.import proc_gate_owner
.import proc_gate_phase
.import proc_gate_wait_head
.import proc_gate_wait_tail
.import proc_gate_next

.import dbg_gate_wait_reason
.import dbg_gate_wait_object

.segment "KERN_TEXT"

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
;   They do not disable scheduling after returning.
; ------------------------------------------------------------

.macro DEFINE_SLEEPABLE_GATE init_proc, acquire_proc, release_proc, enqueue_proc, dequeue_proc, gate_byte, owner_byte, phase_byte, wait_head, wait_tail, next_table, lock_id, idle_phase

.proc init_proc
    stz gate_byte
    lda #idle_phase
    sta phase_byte

    lda #DBG_OWNER_NONE
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
    lda #DBG_OWNER_NONE
    sta next_table,x

    lda wait_tail
    cmp #DBG_OWNER_NONE
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
    cpx #DBG_OWNER_NONE
    bne @have_pid

    sec
    rts

@have_pid:
    lda next_table,x
    sta wait_head
    cmp #DBG_OWNER_NONE
    bne @clear_link

    sta wait_tail

@clear_link:
    lda #DBG_OWNER_NONE
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

    ; DEBUG-BEGIN: detect recursive sleepable gate acquire
    lda owner_byte
    cmp active_pid
    bne @wait_for_owner

    lda #DBG_MARK_GATE_RECURSE
    sta sched_debug_marker
    lda active_pid
    sta sched_debug_pid

    ; Do not hard-hang the system here.  A recursive acquire is
    ; still a kernel bug, but the monitor must remain usable.
    ; Return C clear so checked callers can fail/diagnose instead
    ; of spinning forever.  The original owner keeps the gate.
    plp
    clc
    rts
    ; DEBUG-END: detect recursive sleepable gate acquire

@wait_for_owner:
    ldx active_pid
    jsr enqueue_proc

    lda #WAIT_LOCK
    ; DEBUG-BEGIN: temporary gate wait-object diagnostic
    sta dbg_gate_wait_reason
    ldy #lock_id
    sty dbg_gate_wait_object
    ; DEBUG-END: temporary gate wait-object diagnostic
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

    ; DEBUG-BEGIN: detect invalid sleepable gate release
    lda owner_byte
    cmp active_pid
    beq @owner_ok

    ; DEBUG-BEGIN: temporary gate release diagnostic
    lda #DBG_MARK_GATE_RELEASE
    sta sched_debug_marker
    lda active_pid
    sta sched_debug_pid
    ; DEBUG-END: temporary gate release diagnostic

    ; Do not hard-hang on bad release either.  Leave the gate state
    ; untouched and return C clear for checked callers/monitor output.
    plp
    clc
    rts
    ; DEBUG-END: detect invalid sleepable gate release

@owner_ok:
    lda #DBG_OWNER_NONE
    sta owner_byte

    lda #idle_phase
    sta phase_byte

    lda #$01
    trb gate_byte

    jsr dequeue_proc
    bcs @done

    ; X = FIFO waiter PID.
    jsr proc_wake

@done:
    plp
    sec
    rts
.endproc

.endmacro

; ------------------------------------------------------------
; Concrete gate instances
; ------------------------------------------------------------

DEFINE_SLEEPABLE_GATE file_io_gate_init, file_io_gate_acquire, file_io_gate_release, file_io_gate_enqueue_current, file_io_gate_dequeue_one, file_io_gate, file_io_gate_owner, file_io_gate_phase, file_io_gate_wait_head, file_io_gate_wait_tail, file_io_gate_next, LOCK_ID_FILE_IO, DBG_FILE_IO_IDLE

DEFINE_SLEEPABLE_GATE proc_gate_init, proc_gate_acquire, proc_gate_release, proc_gate_enqueue_current, proc_gate_dequeue_one, proc_gate, proc_gate_owner, proc_gate_phase, proc_gate_wait_head, proc_gate_wait_tail, proc_gate_next, LOCK_ID_PROC, DBG_PROC_GATE_IDLE
