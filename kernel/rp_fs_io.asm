; ============================================================
; rp_fs_io.asm
; NEOX - RP2350 filesystem mailbox command usage
;
; Purpose:
;   Implements read-only filesystem requests using the RP2350
;   mailbox transport and mailbox ABI v2.
;
; Design rule:
;   This file owns filesystem command semantics only. Low-level
;   mailbox locking, waiting, and doorbell mechanics remain in
;   rp2350.asm.
; ============================================================

.setcpu "65C02"

.include "mailbox.inc"
.include "syscall.inc"

.export rp_fs_status
.export rp_fs_open_readonly
.export rp_fs_open_write_trunc
.export rp_fs_read
.export rp_fs_write
.export rp_fs_close

.importzp io_ptr

.import rp_acquire_lock
.import rp_release_lock
.import rp_wait_done
.import rp_mailbox_clear_request
.import rp_mailbox_trigger
.import rp_mailbox_mark_idle

.segment "KERN_TEXT"

; <summary>
; rp_fs_status submits an FS_STATUS command to the RP2350.
; </summary>
; <returns>C clear with A/X = RES0 and Y = FLAGS; C set with Y = errno.</returns>
.proc rp_fs_status
    jsr rp_acquire_lock

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_STATUS
    sta RP_CMD

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES0L
    ldx RP_RES0H
    ldy RP_FLAGS
    pha
    phx
    phy

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    ply
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
; rp_fs_open_readonly submits an FS_OPEN read-only request to the RP2350.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_readonly
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = device
    plx                         ; X = max length high
    pla                         ; A = max length low

    jsr rp_mailbox_clear_request

    pha
    phx
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_OPEN
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ply                         ; Y = device
    plx                         ; X = max length high
    pla                         ; A = max length low

    sta RP_ARG1L
    stx RP_ARG1H

    stz RP_ARG2L                ; flags = 0: read-only
    sty RP_ARG2H                ; device

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES0L                ; handle
    ldx #0
    pha

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    pla
    ldx #0
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
; rp_fs_open_write_trunc submits an FS_OPEN create/truncate write-only request to the RP2350.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_write_trunc
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = device
    plx                         ; X = max length high
    pla                         ; A = max length low

    jsr rp_mailbox_clear_request

    pha
    phx
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_OPEN
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ply                         ; Y = device
    plx                         ; X = max length high
    pla                         ; A = max length low

    sta RP_ARG1L
    stx RP_ARG1H

    lda #OPEN_WRITE_TRUNC       ; flags = create/truncate write-only
    sta RP_ARG2L
    sty RP_ARG2H                ; device

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES0L                ; handle
    ldx #0
    pha

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

    pla
    ldx #0
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
; rp_fs_read submits an FS_READ request for an already-open RP file handle.
; </summary>
; <param name="io_ptr">Destination buffer pointer in caller context.</param>
; <param name="A">Requested read length low byte.</param>
; <param name="X">Requested read length high byte.</param>
; <param name="Y">RP file handle.</param>
; <returns>C clear with A/X = bytes read; C set with Y = errno.</returns>
.proc rp_fs_read
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = handle
    plx                         ; X = length high
    pla                         ; A = length low

    jsr rp_mailbox_clear_request

    pha
    phx
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_READ
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ply                         ; Y = handle
    plx                         ; X = length high
    pla                         ; A = length low

    sta RP_ARG1L
    stx RP_ARG1H
    sty RP_ARG2L
    stz RP_ARG2H

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
; rp_fs_write submits an FS_WRITE request for an already-open RP file handle.
; </summary>
; <param name="io_ptr">Source buffer pointer in caller context.</param>
; <param name="A">Requested write length low byte.</param>
; <param name="X">Requested write length high byte.</param>
; <param name="Y">RP file handle.</param>
; <returns>C clear with A/X = bytes written; C set with Y = errno.</returns>
.proc rp_fs_write
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = handle
    plx                         ; X = length high
    pla                         ; A = length low

    jsr rp_mailbox_clear_request

    pha
    phx
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_WRITE
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ply                         ; Y = handle
    plx                         ; X = length high
    pla                         ; A = length low

    sta RP_ARG1L
    stx RP_ARG1H
    sty RP_ARG2L
    stz RP_ARG2H

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
; rp_fs_close submits an FS_CLOSE request for an RP file handle.
; </summary>
; <param name="A">RP file handle.</param>
; <returns>C clear on success; C set with Y = errno.</returns>
.proc rp_fs_close
    pha

    jsr rp_acquire_lock

    pla

    jsr rp_mailbox_clear_request

    pha

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_CLOSE
    sta RP_CMD

    pla
    sta RP_ARG2L
    stz RP_ARG2H

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    jsr rp_mailbox_mark_idle
    jsr rp_release_lock

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
