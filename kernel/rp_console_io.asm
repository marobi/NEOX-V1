; ============================================================
; rp_console_io.asm
; NEOX - RP2350 console mailbox command usage
;
; Purpose:
;   Implements console read/write requests using the RP2350
;   mailbox transport.
;
; Design rule:
;   This file owns console command semantics only. Low-level
;   mailbox locking, waiting, and doorbell mechanics remain in
;   rp2350.asm.
; ============================================================

.setcpu "65C02"


.include "bios.inc"
.include "mailbox.inc"
.include "syscall.inc"

.export rp_console_write
.export rp_console_read_start
.export rp_console_read_finish
.export rp_console_write_start
.export rp_console_write_finish

.importzp io_ptr

.import rp_acquire_lock
.import rp_release_lock
.import rp_wait_done
.import rp_mailbox_clear_request
.import rp_mailbox_trigger
.import rp_mailbox_mark_idle

.segment "KERN_TEXT"

; <summary>
; rp_console_fill_write_request fills the ABI v2 request block for
; a console write command.
; </summary>
; <param name="A">Length low byte.</param>
; <param name="X">Length high byte.</param>
; <returns>Nothing.</returns>
.proc rp_console_fill_write_request
    pha
    phx

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_CONSOLE
    sta RP_GROUP
    lda #RP_CON_CMD_WRITE
    sta RP_CMD

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
; rp_console_fill_read_request fills the ABI v2 request block for
; a console read command.
; </summary>
; <param name="A">Length low byte.</param>
; <param name="X">Length high byte.</param>
; <returns>Nothing.</returns>
.proc rp_console_fill_read_request
    pha
    phx

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_CONSOLE
    sta RP_GROUP
    lda #RP_CON_CMD_READ
    sta RP_CMD

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
; rp_console_write submits a synchronous console write request to
; the RP2350.
; </summary>
; <param name="io_ptr">Source buffer pointer.</param>
; <param name="A">Length low byte.</param>
; <param name="X">Length high byte.</param>
; <returns>C clear with A/X = bytes written; C set with Y = errno.</returns>
.proc rp_console_write
    pha
    phx

    jsr rp_acquire_lock

    plx
    pla

    jsr rp_console_fill_write_request
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
; rp_console_read_start submits an asynchronous console read request
; and leaves the mailbox lock held until finish completes.
; </summary>
; <param name="io_ptr">Destination buffer pointer.</param>
; <param name="A">Length low byte.</param>
; <param name="X">Length high byte.</param>
; <returns>C clear when the request was submitted.</returns>
.proc rp_console_read_start
    pha
    phx

    jsr rp_acquire_lock

    plx
    pla

    jsr rp_console_fill_read_request
    jsr rp_mailbox_trigger

    clc
    rts
.endproc

; <summary>
; rp_console_read_finish checks completion of an asynchronous console
; read request and releases the mailbox lock only when finished.
; </summary>
; <returns>C clear with A/X = bytes read; C set with Y = E_OK when busy or EIO on failure.</returns>
.proc rp_console_read_finish
    lda RP_STATUS
    cmp #RP_DONE
    beq @done

    cmp #RP_ERROR
    beq @error

    ldy #E_OK
    sec
    rts

@done:
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

@error:
    ldy #EIO
    phy

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    ply
    sec
    rts
.endproc

; <summary>
; rp_console_write_start submits an asynchronous console write request
; and leaves the mailbox lock held until finish completes.
; </summary>
; <param name="io_ptr">Source buffer pointer.</param>
; <param name="A">Length low byte.</param>
; <param name="X">Length high byte.</param>
; <returns>C clear when the request was submitted.</returns>
.proc rp_console_write_start
    pha
    phx

    jsr rp_acquire_lock

    plx
    pla

    jsr rp_console_fill_write_request
    jsr rp_mailbox_trigger

    clc
    rts
.endproc

; <summary>
; rp_console_write_finish checks completion of an asynchronous console
; write request and releases the mailbox lock only when finished.
; </summary>
; <returns>C clear with A/X = bytes written; C set with Y = E_OK when busy or EIO on failure.</returns>
.proc rp_console_write_finish
    lda RP_STATUS
    cmp #RP_DONE
    beq @done

    cmp #RP_ERROR
    beq @error

    ldy #E_OK
    sec
    rts

@done:
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

@error:
    ldy #EIO
    phy

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    ply
    sec
    rts
.endproc

