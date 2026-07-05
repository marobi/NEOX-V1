; ============================================================
; rp_fs_io.asm
; NEOX - RP2350 filesystem mailbox command usage
;
; Purpose:
;   Implements RP filesystem mailbox requests using the RP2350
;   mailbox transport and mailbox ABI v2.
;
; Design rule:
;   This file owns filesystem command semantics only. Low-level
;   mailbox locking, waiting, and doorbell mechanics remain in
;   mailbox.asm.
; ============================================================

.setcpu "65C02"

.include "mailbox.inc"
.include "syscall.inc"

.export rp_fs_status
.export rp_fs_open_readonly
.export rp_fs_open_write_trunc
.export rp_fs_open_write_existing
.export rp_fs_open_rw_existing
.export rp_fs_open_rw_create
.export rp_fs_read
.export rp_fs_write
.export rp_fs_load_file_to_memory
.export rp_fs_save_memory_to_file
.export rp_fs_seek
.export rp_fs_tell
.export rp_fs_delete
.export rp_fs_rename_set_new_path
.export rp_fs_rename
.export rp_fs_opendir
.export rp_fs_readdir
.export rp_fs_closedir
.export rp_fs_mkdir
.export rp_fs_rmdir
.export rp_fs_result_hi_lo
.export rp_fs_result_hi_hi
.export rp_fs_close

.importzp io_ptr

.import rp_acquire_lock
.import rp_release_lock
.import rp_wait_done
.import rp_mailbox_clear_request
.import rp_mailbox_trigger
.import rp_mailbox_mark_idle

.segment "KERN_BSS"

; Mailbox-lock-protected scratch used only by rp_fs_open_mode after
; rp_acquire_lock has completed.
rp_fs_open_mode_tmp:
    .res 1

; Mailbox-lock-protected scratch used by V33 seek/tell.
rp_fs_seek_handle_tmp:
    .res 1

rp_fs_seek_whence_tmp:
    .res 1

; File-IO-gate-protected scratch used by V34 rename.  ksys_rename sets
; this immediately before calling rp_fs_rename while holding file_io_gate.
rp_fs_rename_new_path_lo:
    .res 1

rp_fs_rename_new_path_hi:
    .res 1

; High word from the last successful V33 seek/tell result.  The low word
; is returned in A/X.  Kernel syscall code reads these bytes immediately
; after rp_fs_seek/rp_fs_tell returns and before any later RP transaction.
rp_fs_result_hi_lo:
    .res 1

rp_fs_result_hi_hi:
    .res 1

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
; rp_fs_open_mode submits an FS_OPEN request to the RP2350 with the
; selected V32 open mode. The caller wrapper pushes max_len low and
; open mode before tail-calling this routine.
; </summary>
; <param name="stack">Top byte = open mode; next byte = max_len low.</param>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_mode
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = device
    plx                         ; X = max length high
    pla                         ; A = open mode
    sta rp_fs_open_mode_tmp
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
    lda rp_fs_open_mode_tmp
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
; rp_fs_open_readonly submits an FS_OPEN read-only request to the RP2350.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_readonly
    pha
    lda #OPEN_READ
    pha
    jmp rp_fs_open_mode
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
    lda #OPEN_WRITE_TRUNC
    pha
    jmp rp_fs_open_mode
.endproc

; <summary>
; rp_fs_open_write_existing submits an FS_OPEN write-only existing-file request
; without truncation.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_write_existing
    pha
    lda #OPEN_WRITE_EXISTING
    pha
    jmp rp_fs_open_mode
.endproc

; <summary>
; rp_fs_open_rw_existing submits an FS_OPEN read/write existing-file request
; without truncation.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_rw_existing
    pha
    lda #OPEN_RW_EXISTING
    pha
    jmp rp_fs_open_mode
.endproc

; <summary>
; rp_fs_open_rw_create submits an FS_OPEN read/write create-if-missing request
; without truncating an existing file.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP file handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_open_rw_create
    pha
    lda #OPEN_RW_CREATE
    pha
    jmp rp_fs_open_mode
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
; rp_fs_seek submits an FS_SEEK request using standard SEEK_SET/CUR/END
; semantics.  io_ptr points to a four-byte signed offset in kernel memory.
; </summary>
; <param name="A">RP file handle.</param>
; <param name="Y">Seek origin: RP_FS_SEEK_SET, RP_FS_SEEK_CUR, or RP_FS_SEEK_END.</param>
; <param name="io_ptr">Pointer to signed 32-bit offset bytes, low word first.</param>
; <returns>C clear with A/X = result low word and rp_fs_result_hi_* = result high word; C set with Y = errno.</returns>
.proc rp_fs_seek
    pha
    phy

    jsr rp_acquire_lock

    ply
    pla
    sta rp_fs_seek_handle_tmp
    sty rp_fs_seek_whence_tmp

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_SEEK
    sta RP_CMD

    ldy #0
    lda (io_ptr),y
    sta RP_ARG0L
    iny
    lda (io_ptr),y
    sta RP_ARG0H
    iny
    lda (io_ptr),y
    sta RP_ARG1L
    iny
    lda (io_ptr),y
    sta RP_ARG1H

    lda rp_fs_seek_handle_tmp
    sta RP_ARG2L
    lda rp_fs_seek_whence_tmp
    sta RP_ARG2H

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES1L
    sta rp_fs_result_hi_lo
    lda RP_RES1H
    sta rp_fs_result_hi_hi

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
; rp_fs_tell submits an FS_TELL request for an already-open RP file handle.
; </summary>
; <param name="A">RP file handle.</param>
; <returns>C clear with A/X = result low word and rp_fs_result_hi_* = result high word; C set with Y = errno.</returns>
.proc rp_fs_tell
    pha

    jsr rp_acquire_lock

    pla
    sta rp_fs_seek_handle_tmp

    jsr rp_mailbox_clear_request

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_TELL
    sta RP_CMD

    lda rp_fs_seek_handle_tmp
    sta RP_ARG2L
    stz RP_ARG2H

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES1L
    sta rp_fs_result_hi_lo
    lda RP_RES1H
    sta rp_fs_result_hi_hi

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
; rp_fs_delete submits an FS_DELETE request for a bounded 8.3 path.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length low byte.</param>
; <param name="X">Maximum filename scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc rp_fs_delete
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
    lda #RP_FS_CMD_DELETE
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
; rp_fs_rename_set_new_path stores the new-path pointer for rp_fs_rename.
; </summary>
; <param name="A/X">Pointer to the new NUL-terminated filename in caller context.</param>
; <returns>C clear.</returns>
.proc rp_fs_rename_set_new_path
    sta rp_fs_rename_new_path_lo
    stx rp_fs_rename_new_path_hi
    clc
    rts
.endproc

; <summary>
; rp_fs_rename submits an FS_RENAME request for bounded 8.3 paths.
; </summary>
; <param name="io_ptr">Pointer to old NUL-terminated filename in caller context.</param>
; <param name="A">Maximum filename scan length, low byte only.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc rp_fs_rename
    pha
    phy

    jsr rp_acquire_lock

    ply                         ; Y = device
    pla                         ; A = max length low

    jsr rp_mailbox_clear_request

    pha
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_RENAME
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    lda rp_fs_rename_new_path_lo
    sta RP_ARG1L
    lda rp_fs_rename_new_path_hi
    sta RP_ARG1H

    ply                         ; Y = device
    pla                         ; A = max length low

    sta RP_ARG2L
    sty RP_ARG2H

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
; rp_fs_opendir submits an FS_OPENDIR request for an explicit directory path.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated explicit directory path in caller context.</param>
; <param name="A">Maximum path scan length low byte.</param>
; <param name="X">Maximum path scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A = RP directory handle and X = 0; C set with Y = errno.</returns>
.proc rp_fs_opendir
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
    lda #RP_FS_CMD_OPENDIR
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
    sty RP_ARG2L
    stz RP_ARG2H

    jsr rp_mailbox_trigger
    jsr rp_wait_done
    bcs @fail

    lda RP_RES0L                ; RP directory handle
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
; rp_fs_readdir submits an FS_READDIR request for an already-open RP directory handle.
; </summary>
; <param name="io_ptr">Destination dir_entry buffer pointer in caller context.</param>
; <param name="A">Destination buffer size low byte.</param>
; <param name="X">Destination buffer size high byte.</param>
; <param name="Y">RP directory handle.</param>
; <returns>C clear with A/X = 1 when an entry was returned or 0 at EOF; C set with Y = errno.</returns>
.proc rp_fs_readdir
    pha
    phx
    phy

    jsr rp_acquire_lock

    ply                         ; Y = RP directory handle
    plx                         ; X = entry buffer size high
    pla                         ; A = entry buffer size low

    jsr rp_mailbox_clear_request

    pha
    phx
    phy

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_READDIR
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ply                         ; Y = RP directory handle
    plx                         ; X = entry buffer size high
    pla                         ; A = entry buffer size low

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
; rp_fs_closedir submits an FS_CLOSEDIR request for an RP directory handle.
; </summary>
; <param name="A">RP directory handle.</param>
; <returns>C clear on success; C set with Y = errno.</returns>
.proc rp_fs_closedir
    pha

    jsr rp_acquire_lock

    pla

    jsr rp_mailbox_clear_request

    pha

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_CLOSEDIR
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

; <summary>
; rp_fs_mkdir submits an FS_MKDIR request for a bounded explicit 8.3 directory path.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated directory path in caller context.</param>
; <param name="A">Maximum path scan length low byte.</param>
; <param name="X">Maximum path scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc rp_fs_mkdir
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
    lda #RP_FS_CMD_MKDIR
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
; rp_fs_rmdir submits an FS_RMDIR request for a bounded explicit 8.3 directory path.
; </summary>
; <param name="io_ptr">Pointer to a NUL-terminated directory path in caller context.</param>
; <param name="A">Maximum path scan length low byte.</param>
; <param name="X">Maximum path scan length high byte.</param>
; <param name="Y">Filesystem device/FatFs drive number.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc rp_fs_rmdir
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
    lda #RP_FS_CMD_RMDIR
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
; rp_fs_load_file_to_memory submits an FS_LOAD bulk request to the RP2350.
; </summary>
; <param name="io_ptr">Pointer to an fs_load_args block in the caller context.</param>
; <param name="A">Trusted caller context, supplied by the kernel.</param>
; <returns>C clear with A/X = bytes loaded; C set with Y = errno.</returns>
.proc rp_fs_load_file_to_memory
    pha

    jsr rp_acquire_lock

    pla                         ; A = trusted caller context

    jsr rp_mailbox_clear_request

    pha

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_LOAD
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    lda #FS_LOAD_ARGS_SIZE
    sta RP_ARG1L
    stz RP_ARG1H

    pla                         ; A = trusted caller context
    sta RP_ARG2L
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
; rp_fs_save_memory_to_file submits an FS_SAVE bulk request to the RP2350.
; </summary>
; <param name="io_ptr">Pointer to an fs_save_args block in the caller context.</param>
; <param name="A">Trusted caller context, supplied by the kernel.</param>
; <returns>C clear with A/X = bytes saved; C set with Y = errno.</returns>
.proc rp_fs_save_memory_to_file
    pha

    jsr rp_acquire_lock

    pla                         ; A = trusted caller context

    jsr rp_mailbox_clear_request

    pha

    lda #RP_GROUP_FS
    sta RP_GROUP
    lda #RP_FS_CMD_SAVE
    sta RP_CMD

    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    lda #FS_SAVE_ARGS_SIZE
    sta RP_ARG1L
    stz RP_ARG1H

    pla                         ; A = trusted caller context
    sta RP_ARG2L
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
