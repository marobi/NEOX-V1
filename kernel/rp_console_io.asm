; ============================================================
; rp_console_io.asm
; NEOX - RP2350 console mailbox command usage
;
; Purpose:
;   Implements synchronous console read/write requests through
;   the shared RP2350 mailbox transport.
; ============================================================

.setcpu "65C02"

.include "mailbox.inc"

.export rp_console_read
.export rp_console_write

.importzp io_ptr

.import rp_acquire_lock
.import rp_release_lock
.import rp_wait_done
.import rp_mailbox_clear_request
.import rp_mailbox_trigger
.import rp_mailbox_mark_idle

.segment "KERN_TEXT"

; <summary>
; Fills the common ABI-v2 console request fields.
; </summary>
; <param name="A">Transfer length low byte.</param>
; <param name="X">Transfer length high byte.</param>
; <param name="Y">RP_CON_CMD_READ or RP_CON_CMD_WRITE.</param>
; <returns>Nothing.</returns>
.proc rp_console_fill_request
    pha
    phx
    phy

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_CONSOLE
    sta RP_GROUP

    ply
    sty RP_CMD
    plx
    pla

    sta RP_ARG1L
    stx RP_ARG1H

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H
    rts
.endproc

; <summary>
; Submits one synchronous console mailbox transfer.
; </summary>
; <param name="io_ptr">Caller buffer pointer.</param>
; <param name="A">Transfer length low byte.</param>
; <param name="X">Transfer length high byte.</param>
; <param name="Y">RP_CON_CMD_READ or RP_CON_CMD_WRITE.</param>
; <returns>C clear with A/X = bytes transferred; C set with Y = errno.</returns>
.proc rp_console_transfer
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply
    plx
    pla

    jsr rp_console_fill_request
    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES0L
    ldx RP_RES0H
    pha
    phx

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    plx
    pla
    clc
    rts

@fail:
    phy
    jsr rp_mailbox_mark_idle
    jsr rp_release_lock
    ply
    sec
    rts
.endproc

; <summary>
; Reads console bytes synchronously through the RP2350 mailbox.
; </summary>
; <param name="io_ptr">Destination buffer pointer.</param>
; <param name="A">Requested length low byte.</param>
; <param name="X">Requested length high byte.</param>
; <returns>C clear with A/X = bytes read; C set with Y = errno.</returns>
.proc rp_console_read
    ldy #RP_CON_CMD_READ
    jmp rp_console_transfer
.endproc

; <summary>
; Writes console bytes synchronously through the RP2350 mailbox.
; </summary>
; <param name="io_ptr">Source buffer pointer.</param>
; <param name="A">Requested length low byte.</param>
; <param name="X">Requested length high byte.</param>
; <returns>C clear with A/X = bytes written; C set with Y = errno.</returns>
.proc rp_console_write
    ldy #RP_CON_CMD_WRITE
    jmp rp_console_transfer
.endproc
