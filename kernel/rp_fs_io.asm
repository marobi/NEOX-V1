; ============================================================
; rp_fs_io.asm
; NEOX - RP2350 filesystem mailbox command usage
;
; Purpose:
;   Implements the single generic RP filesystem request transport.
;
; Design rule:
;   Filesystem operation semantics live on the RP2350. This module owns only
;   request publication, WAIT_RP blocking, completion collection, and the
;   PID 0 polling exception.
; ============================================================

.setcpu "65C02"

.include "mailbox.inc"
.include "process.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"

.export rp_fs_exec

.importzp io_ptr

.import rp_wait_done
.import rp_mailbox_clear_request
.import rp_mailbox_trigger
.import rp_mailbox_mark_idle

.import active_pid
.import proc_context
.import proc_set_wait
.import sched_yield
.import file_io_gate_owner

.segment "KERN_TEXT"

; <summary>
; rp_fs_exec submits one compact generic filesystem request. The caller owns
; file_io_gate for the complete transaction. Normal processes block in WAIT_RP
; while retaining the gate; PID 0 polls the same request to support cleanup.
; </summary>
; <param name="A">Filesystem operation code written to RP_STATE.</param>
; <param name="X">Trusted RP handle, or $FF when not applicable.</param>
; <param name="Y">Operation-specific auxiliary byte.</param>
; <param name="io_ptr">Pointer to the caller syscall argument block, or zero.</param>
; <returns>C clear with A/X = RES0 and Y = FLAGS; C set with Y = errno.</returns>
.proc rp_fs_exec
    ; Preserve compact call inputs until ownership/invariant checks complete.
    pha
    phx
    phy

    lda file_io_gate_owner
    cmp active_pid
    beq @owner_ok
    jmp @invariant_fail

@owner_ok:
    lda RP_STATUS
    cmp #RP_IDLE
    beq @mailbox_idle
    jmp @invariant_fail

@mailbox_idle:
    jsr rp_mailbox_clear_request

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_EXEC
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ; Restore request values into their compact mailbox fields.
    ply                             ; auxiliary
    plx                             ; rp_handle
    pla                             ; operation
    sta RP_STATE
    stx RP_ARG2L
    sty RP_ARG2H

    ldx active_pid
    stx RP_ARG1L
    lda proc_context,x
    sta RP_ARG1H

    cpx #IDLE_PID
    beq @poll

    ; Commit WAIT_RP before ringing the doorbell. An immediate RP completion
    ; therefore cannot arrive before the owner has a valid blocked state.
    php
    sei
    lda #WAIT_RP
    ldy RP_STATE
    jsr proc_set_wait

    lda #RP_BUSY
    sta RP_STATUS
    lda #RP_DOORBELL_TRIGGER
    sta RP_DOORBELL

    pla                             ; discard entry P; sched_yield builds RTI frame
    jsr sched_yield
    bra @collect

@poll:
    ; PID 0 has no normal saved continuation and therefore polls. The RP does
    ; not generate an FS completion IRQ when request PID is zero.
    jsr rp_mailbox_trigger
    jsr rp_wait_done

@collect:
    lda RP_STATUS
    cmp #RP_DONE
    beq @done

    cmp #RP_ERROR
    beq @error

    ; A wake without a terminal mailbox status violates the single-request
    ; protocol. Return EIO after restoring mailbox ownership to IDLE.
    ldy #EIO
    bra @error_with_y

@done:
    lda RP_RES0L
    ldx RP_RES0H
    ldy RP_FLAGS
    pha
    phx
    phy

    jsr rp_mailbox_mark_idle

    ply
    plx
    pla
    clc
    rts

@error:
    ldy RP_ERR

@error_with_y:
    phy
    jsr rp_mailbox_mark_idle
    ply
    sec
    rts

@invariant_fail:
    ply
    plx
    pla
    ldy #EIO
    sec
    rts
.endproc
