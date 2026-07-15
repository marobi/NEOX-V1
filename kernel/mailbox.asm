; ============================================================
; mailbox.asm
; NEOX - RP2350 mailbox transport helpers
;
; Purpose:
;   Provides only the low-level kernel-side mailbox transport
;   used to communicate with the RP2350 co-processor.
;
; Architecture:
;   - Request/result block lives in shared RAM at RP_REQ_BASE.
;   - Doorbell register lives in shared I/O space.
;   - rp_lock serializes mailbox ownership.
;
; Design rule:
;   This file is mechanism only. Command-specific mailbox usage
;   belongs in separate modules such as rp_console_io.asm.
; ============================================================

.setcpu "65C02"


.include "bios.inc"
.include "kernel.inc"
.include "mailbox.inc"
.include "syscall.inc"
.include "lock.inc"

.export rp_try_acquire_lock
.export rp_acquire_lock
.export rp_release_lock
.export rp_wait_done
.export rp_mailbox_clear_request
.export rp_mailbox_trigger
.export rp_mailbox_mark_idle

.import rp_lock

.segment "KERN_TEXT"

; <summary>
; rp_try_acquire_lock attempts to acquire exclusive ownership of
; the shared RP2350 mailbox interface.
; </summary>
; <returns>C set when acquired; C clear when busy.</returns>
.proc rp_try_acquire_lock
    LOCK_TRY_ACQUIRE rp_lock
    rts
.endproc

; <summary>
; rp_acquire_lock waits until mailbox ownership is acquired and
; verifies that the shared mailbox is idle before returning.
; </summary>
; <returns>C set on return.</returns>
.proc rp_acquire_lock
@wait_lock:
    jsr rp_try_acquire_lock
    bcc @wait_lock

    lda RP_STATUS
    cmp #RP_IDLE
    beq @ok

@bad:
    bra @bad

@ok:
    sec
    rts
.endproc

; <summary>
; rp_release_lock releases mailbox ownership after verifying that
; the shared mailbox has been returned to RP_IDLE.
; </summary>
; <returns>C set on return.</returns>
.proc rp_release_lock
    lda RP_STATUS
    cmp #RP_IDLE
    beq @release

@bad:
    bra @bad

@release:
    LOCK_RELEASE rp_lock
    rts
.endproc


; <summary>
; rp_wait_done waits until RP_STATUS reports completion or failure.
; </summary>
; <returns>C clear on RP_DONE; C set on RP_ERROR with Y = RP_ERR.</returns>
.proc rp_wait_done
@loop:
    lda RP_STATUS
    cmp #RP_DONE
    beq @done
    cmp #RP_ERROR
    beq @error
    bra @loop

@done:
    clc
    rts

@error:
    ldy RP_ERR
    sec
    rts
.endproc

; <summary>
; rp_mailbox_clear_request clears ABI v2 request/result fields
; owned by the mailbox transaction.
; </summary>
; <returns>Nothing.</returns>
.proc rp_mailbox_clear_request
    stz RP_GROUP
    stz RP_CMD
    stz RP_ERR
    stz RP_FLAGS
    stz RP_STATE
    stz RP_ARG0L
    stz RP_ARG0H
    stz RP_ARG1L
    stz RP_ARG1H
    stz RP_ARG2L
    stz RP_ARG2H
    stz RP_RES0L
    stz RP_RES0H
    stz RP_RES1L
    stz RP_RES1H
    rts
.endproc

; <summary>
; rp_mailbox_trigger marks the mailbox busy and rings the RP2350
; doorbell using the ABI v2 trigger-only doorbell value.
; </summary>
; <returns>Nothing.</returns>
.proc rp_mailbox_trigger
    php
    sei

    lda #RP_BUSY
    sta RP_STATUS

    lda #RP_DOORBELL_TRIGGER
    sta RP_DOORBELL

    plp
    rts
.endproc

; <summary>
; rp_mailbox_mark_idle returns the shared mailbox status byte to
; RP_IDLE after a completed or failed transaction.
; </summary>
; <returns>Nothing.</returns>
.proc rp_mailbox_mark_idle
    lda #RP_IDLE
    sta RP_STATUS
    rts
.endproc
