; ============================================================
; ksys_fs.asm
; NEOX - kernel filesystem syscall services
;
; Purpose:
;   Owns filesystem syscall entry points that integrate RP2350
;   mailbox filesystem handles into the FD/open-object layer.
;
; Current scope:
;   - read-only open via RP FS mailbox ABI v2
;   - read through normal sys_read/FD path
;   - close through normal sys_close/FD path
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "fd.inc"

.export ksys_open

.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_phase
.import active_pid

.import fd_alloc_open
.import fd_free_open
.import fd_alloc_fd_current
.import fd_attach_current

.import open_type
.import open_flags
.import open_dev
.import open_file_handle

.import rp_fs_open_readonly

.importzp io_ptr

.segment "KERN_BSS"

; Per-PID open syscall argument snapshot. The syscall entry pointer is
; copied before file_io_gate_acquire because the gate can block/yield.
ksys_open_path_lo_by_pid:
    .res MAX_PROCS

ksys_open_path_hi_by_pid:
    .res MAX_PROCS

ksys_open_max_lo_by_pid:
    .res MAX_PROCS

ksys_open_max_hi_by_pid:
    .res MAX_PROCS

ksys_open_flags_by_pid:
    .res MAX_PROCS

ksys_open_device_by_pid:
    .res MAX_PROCS

; Gate-protected scratch. Valid only while file_io_gate is owned.
ksys_open_path_lo:
    .res 1

ksys_open_path_hi:
    .res 1

ksys_open_max_lo:
    .res 1

ksys_open_max_hi:
    .res 1

ksys_open_flags:
    .res 1

ksys_open_device:
    .res 1

ksys_open_obj:
    .res 1

ksys_open_fd:
    .res 1

ksys_open_entry_lo:
    .res 1

ksys_open_entry_hi:
    .res 1

.segment "KERN_TEXT"

; <summary>
; ksys_open implements open(path, flags, device) for read-only RP filesystem
; files and attaches the resulting RP handle to the current process FD table.
; </summary>
; <param name="X/Y">Pointer to an open_args block in the caller context.</param>
; <returns>C clear with A = fd and X = 0; C set with Y = errno.</returns>
.proc ksys_open
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_open_entry_lo
    sty ksys_open_entry_hi

    lda ksys_open_entry_lo
    sta io_ptr
    lda ksys_open_entry_hi
    sta io_ptr+1

    ldx active_pid

    ldy #open_args::path_ptr
    lda (io_ptr),y
    sta ksys_open_path_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_open_path_hi_by_pid,x

    ldy #open_args::max_len
    lda (io_ptr),y
    sta ksys_open_max_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_open_max_hi_by_pid,x

    ldy #open_args::flags
    lda (io_ptr),y
    sta ksys_open_flags_by_pid,x

    ldy #open_args::device
    lda (io_ptr),y
    sta ksys_open_device_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ; Copy per-PID snapshot into gate-protected scratch.
    ldx active_pid
    lda ksys_open_path_lo_by_pid,x
    sta ksys_open_path_lo
    lda ksys_open_path_hi_by_pid,x
    sta ksys_open_path_hi
    lda ksys_open_max_lo_by_pid,x
    sta ksys_open_max_lo
    lda ksys_open_max_hi_by_pid,x
    sta ksys_open_max_hi
    lda ksys_open_flags_by_pid,x
    sta ksys_open_flags
    lda ksys_open_device_by_pid,x
    sta ksys_open_device

    ; Only read-only open is supported for now.
    lda ksys_open_flags
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    jsr fd_alloc_open
    bcc @open_obj_ok

    jmp @fail_release

@open_obj_ok:
    stx ksys_open_obj

    jsr fd_alloc_fd_current
    bcc @fd_ok

    ; No process FD slot. Free the open-object slot and fail.
    ldx ksys_open_obj
    jsr fd_free_open
    jmp @fail_release

@fd_ok:
    sty ksys_open_fd

    ; Submit RP FS_OPEN. The RP handle is stored in the open object only
    ; after the RP-side open succeeds.
    lda ksys_open_path_lo
    sta io_ptr
    lda ksys_open_path_hi
    sta io_ptr+1

    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_readonly
    bcc @rp_open_ok

    ; RP open failed. Free the open-object slot; no FD was attached yet.
    ldx ksys_open_obj
    jsr fd_free_open
    jmp @fail_release

@rp_open_ok:
    ; A = RP file handle.
    ldx ksys_open_obj
    sta open_file_handle,x

    lda #OBJ_FILE
    sta open_type,x
    lda #FD_FLAG_READ
    sta open_flags,x
    lda ksys_open_device
    sta open_dev,x

    ; Attach open object to current process FD table. Refcount becomes 1.
    ldx ksys_open_obj
    ldy ksys_open_fd
    lda #FD_FLAG_READ
    jsr fd_attach_current

    lda ksys_open_fd
    pha

    jsr file_io_gate_release

    pla
    ldx #0
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc
