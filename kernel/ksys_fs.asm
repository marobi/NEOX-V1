; ============================================================
; ksys_fs.asm
; NEOX - kernel filesystem syscall services
;
; Purpose:
;   Owns filesystem syscall entry points that integrate RP2350
;   mailbox filesystem handles into the FD/open-object layer.
;
; Current scope:
;   - V32 open modes via RP FS mailbox ABI v2
;   - V33 seek/tell through RP FS mailbox ABI v2
;   - V34 delete/rename through RP FS mailbox ABI v2
;   - V35 opendir/readdir/closedir through RP FS mailbox ABI v2
;   - read/write through normal sys_read/sys_write FD path
;   - close through normal sys_close/FD path
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "fd.inc"

.export ksys_open
.export ksys_load_file_to_memory
.export ksys_save_memory_to_file
.export ksys_seek
.export ksys_tell
.export ksys_delete
.export ksys_rename
.export ksys_opendir
.export ksys_readdir
.export ksys_closedir

.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_phase
.import active_pid
.import proc_context

.import fd_alloc_open
.import fd_free_open
.import fd_alloc_fd_current
.import fd_attach_current
.import fd_resolve_file
.import fd_resolve_dir
.import fd_close

.import open_type
.import open_flags
.import open_dev
.import open_file_handle

.import rp_fs_open_readonly
.import rp_fs_open_write_trunc
.import rp_fs_open_write_existing
.import rp_fs_open_rw_existing
.import rp_fs_open_rw_create
.import rp_fs_load_file_to_memory
.import rp_fs_save_memory_to_file
.import rp_fs_seek
.import rp_fs_tell
.import rp_fs_delete
.import rp_fs_rename
.import rp_fs_rename_set_new_path
.import rp_fs_opendir
.import rp_fs_readdir
.import rp_fs_result_hi_lo
.import rp_fs_result_hi_hi

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


; Per-PID bulk filesystem syscall snapshot. The syscall entry pointer and
; trusted caller context are copied before file_io_gate_acquire because the
; gate can block/yield.
ksys_bulk_args_lo_by_pid:
    .res MAX_PROCS

ksys_bulk_args_hi_by_pid:
    .res MAX_PROCS

ksys_bulk_context_by_pid:
    .res MAX_PROCS

; Per-PID seek/tell syscall snapshots.  The syscall argument pointer and
; input values are copied before file_io_gate_acquire because the gate can
; block/yield.
ksys_seek_args_lo_by_pid:
    .res MAX_PROCS

ksys_seek_args_hi_by_pid:
    .res MAX_PROCS

ksys_seek_fd_by_pid:
    .res MAX_PROCS

ksys_seek_whence_by_pid:
    .res MAX_PROCS

ksys_seek_off0_by_pid:
    .res MAX_PROCS

ksys_seek_off1_by_pid:
    .res MAX_PROCS

ksys_seek_off2_by_pid:
    .res MAX_PROCS

ksys_seek_off3_by_pid:
    .res MAX_PROCS

ksys_tell_args_lo_by_pid:
    .res MAX_PROCS

ksys_tell_args_hi_by_pid:
    .res MAX_PROCS

ksys_tell_fd_by_pid:
    .res MAX_PROCS

; Per-PID delete/rename syscall snapshots.  User pointers and scalar
; arguments are copied before file_io_gate_acquire because the gate can
; block/yield.
ksys_delete_args_lo_by_pid:
    .res MAX_PROCS

ksys_delete_args_hi_by_pid:
    .res MAX_PROCS

ksys_delete_path_lo_by_pid:
    .res MAX_PROCS

ksys_delete_path_hi_by_pid:
    .res MAX_PROCS

ksys_delete_max_lo_by_pid:
    .res MAX_PROCS

ksys_delete_max_hi_by_pid:
    .res MAX_PROCS

ksys_delete_device_by_pid:
    .res MAX_PROCS

ksys_delete_flags_by_pid:
    .res MAX_PROCS

ksys_rename_args_lo_by_pid:
    .res MAX_PROCS

ksys_rename_args_hi_by_pid:
    .res MAX_PROCS

ksys_rename_old_lo_by_pid:
    .res MAX_PROCS

ksys_rename_old_hi_by_pid:
    .res MAX_PROCS

ksys_rename_new_lo_by_pid:
    .res MAX_PROCS

ksys_rename_new_hi_by_pid:
    .res MAX_PROCS

ksys_rename_max_lo_by_pid:
    .res MAX_PROCS

ksys_rename_max_hi_by_pid:
    .res MAX_PROCS

ksys_rename_device_by_pid:
    .res MAX_PROCS

ksys_rename_flags_by_pid:
    .res MAX_PROCS


; Per-PID directory syscall snapshots.  User pointers and scalar
; arguments are copied before file_io_gate_acquire because the gate can
; block/yield.
ksys_opendir_args_lo_by_pid:
    .res MAX_PROCS

ksys_opendir_args_hi_by_pid:
    .res MAX_PROCS

ksys_opendir_path_lo_by_pid:
    .res MAX_PROCS

ksys_opendir_path_hi_by_pid:
    .res MAX_PROCS

ksys_opendir_max_lo_by_pid:
    .res MAX_PROCS

ksys_opendir_max_hi_by_pid:
    .res MAX_PROCS

ksys_opendir_device_by_pid:
    .res MAX_PROCS

ksys_opendir_flags_by_pid:
    .res MAX_PROCS

ksys_readdir_args_lo_by_pid:
    .res MAX_PROCS

ksys_readdir_args_hi_by_pid:
    .res MAX_PROCS

ksys_readdir_fd_by_pid:
    .res MAX_PROCS

ksys_readdir_entry_lo_by_pid:
    .res MAX_PROCS

ksys_readdir_entry_hi_by_pid:
    .res MAX_PROCS

ksys_readdir_size_lo_by_pid:
    .res MAX_PROCS

ksys_readdir_size_hi_by_pid:
    .res MAX_PROCS

ksys_closedir_args_lo_by_pid:
    .res MAX_PROCS

ksys_closedir_args_hi_by_pid:
    .res MAX_PROCS

ksys_closedir_fd_by_pid:
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


ksys_bulk_args_lo:
    .res 1

ksys_bulk_args_hi:
    .res 1

ksys_bulk_context:
    .res 1

ksys_bulk_entry_lo:
    .res 1

ksys_bulk_entry_hi:
    .res 1

ksys_seek_args_lo:
    .res 1

ksys_seek_args_hi:
    .res 1

ksys_seek_fd:
    .res 1

ksys_seek_whence:
    .res 1

ksys_seek_off0:
    .res 1

ksys_seek_off1:
    .res 1

ksys_seek_off2:
    .res 1

ksys_seek_off3:
    .res 1

ksys_seek_result0:
    .res 1

ksys_seek_result1:
    .res 1

ksys_seek_result2:
    .res 1

ksys_seek_result3:
    .res 1

ksys_seek_entry_lo:
    .res 1

ksys_seek_entry_hi:
    .res 1

ksys_tell_args_lo:
    .res 1

ksys_tell_args_hi:
    .res 1

ksys_tell_fd:
    .res 1

ksys_tell_result0:
    .res 1

ksys_tell_result1:
    .res 1

ksys_tell_result2:
    .res 1

ksys_tell_result3:
    .res 1

ksys_tell_entry_lo:
    .res 1

ksys_tell_entry_hi:
    .res 1

ksys_delete_args_lo:
    .res 1

ksys_delete_args_hi:
    .res 1

ksys_delete_path_lo:
    .res 1

ksys_delete_path_hi:
    .res 1

ksys_delete_max_lo:
    .res 1

ksys_delete_max_hi:
    .res 1

ksys_delete_device:
    .res 1

ksys_delete_flags:
    .res 1

ksys_delete_entry_lo:
    .res 1

ksys_delete_entry_hi:
    .res 1

ksys_rename_args_lo:
    .res 1

ksys_rename_args_hi:
    .res 1

ksys_rename_old_lo:
    .res 1

ksys_rename_old_hi:
    .res 1

ksys_rename_new_lo:
    .res 1

ksys_rename_new_hi:
    .res 1

ksys_rename_max_lo:
    .res 1

ksys_rename_max_hi:
    .res 1

ksys_rename_device:
    .res 1

ksys_rename_flags:
    .res 1

ksys_rename_entry_lo:
    .res 1

ksys_rename_entry_hi:
    .res 1


ksys_opendir_args_lo:
    .res 1

ksys_opendir_args_hi:
    .res 1

ksys_opendir_path_lo:
    .res 1

ksys_opendir_path_hi:
    .res 1

ksys_opendir_max_lo:
    .res 1

ksys_opendir_max_hi:
    .res 1

ksys_opendir_device:
    .res 1

ksys_opendir_flags:
    .res 1

ksys_opendir_obj:
    .res 1

ksys_opendir_fd:
    .res 1

ksys_opendir_entry_lo:
    .res 1

ksys_opendir_entry_hi:
    .res 1

ksys_readdir_args_lo:
    .res 1

ksys_readdir_args_hi:
    .res 1

ksys_readdir_fd:
    .res 1

ksys_readdir_entry_lo:
    .res 1

ksys_readdir_entry_hi:
    .res 1

ksys_readdir_size_lo:
    .res 1

ksys_readdir_size_hi:
    .res 1

ksys_readdir_entry_arg_lo:
    .res 1

ksys_readdir_entry_arg_hi:
    .res 1

ksys_closedir_args_lo:
    .res 1

ksys_closedir_args_hi:
    .res 1

ksys_closedir_fd:
    .res 1

ksys_closedir_entry_lo:
    .res 1

ksys_closedir_entry_hi:
    .res 1

.segment "KERN_TEXT"

; <summary>
; ksys_open implements open(path, mode, device) for RP filesystem files
; and attaches the resulting RP handle to the current process FD table.
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

    ; Supported V32 modes:
    ;   OPEN_READ           = read existing file
    ;   OPEN_WRITE_TRUNC    = create/truncate write-only file
    ;   OPEN_WRITE_EXISTING = write existing file without truncation
    ;   OPEN_RW_EXISTING    = read/write existing file without truncation
    ;   OPEN_RW_CREATE      = read/write create-if-missing without truncation
    lda ksys_open_flags
    cmp #OPEN_READ
    beq @flags_ok
    cmp #OPEN_WRITE_TRUNC
    beq @flags_ok
    cmp #OPEN_WRITE_EXISTING
    beq @flags_ok
    cmp #OPEN_RW_EXISTING
    beq @flags_ok
    cmp #OPEN_RW_CREATE
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

    lda ksys_open_flags
    cmp #OPEN_READ
    beq @rp_open_read
    cmp #OPEN_WRITE_TRUNC
    beq @rp_open_write_trunc
    cmp #OPEN_WRITE_EXISTING
    beq @rp_open_write_existing
    cmp #OPEN_RW_EXISTING
    beq @rp_open_rw_existing
    ; Remaining validated mode is OPEN_RW_CREATE.
    bra @rp_open_rw_create

@rp_open_read:
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_readonly
    bcc @rp_open_ok_read
    jmp @rp_open_fail

@rp_open_write_trunc:
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_write_trunc
    bcc @rp_open_ok_write
    jmp @rp_open_fail

@rp_open_write_existing:
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_write_existing
    bcc @rp_open_ok_write
    jmp @rp_open_fail

@rp_open_rw_existing:
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_rw_existing
    bcc @rp_open_ok_rw
    jmp @rp_open_fail

@rp_open_rw_create:
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr rp_fs_open_rw_create
    bcc @rp_open_ok_rw
    jmp @rp_open_fail

@rp_open_ok_read:
    ldy #FD_FLAG_READ
    bra @rp_open_ok

@rp_open_ok_write:
    ldy #FD_FLAG_WRITE
    bra @rp_open_ok

@rp_open_ok_rw:
    ldy #(FD_FLAG_READ | FD_FLAG_WRITE)
    bra @rp_open_ok

@rp_open_fail:
    ; RP open failed. Free the open-object slot; no FD was attached yet.
    ldx ksys_open_obj
    jsr fd_free_open
    jmp @fail_release

@rp_open_ok:
    ; A = RP file handle, Y = FD/open flags.
    phy
    ldx ksys_open_obj
    sta open_file_handle,x

    lda #OBJ_FILE
    sta open_type,x
    ply
    tya
    sta open_flags,x
    lda ksys_open_device
    sta open_dev,x

    ; Attach open object to current process FD table. Refcount becomes 1.
    ldx ksys_open_obj
    ldy ksys_open_fd
    lda open_flags,x
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

; <summary>
; ksys_snapshot_bulk_args copies the user argument pointer and the trusted
; caller context before file_io_gate_acquire can block/yield.
; </summary>
; <param name="X/Y">Pointer to fs_load_args or fs_save_args in caller context.</param>
; <returns>C clear.</returns>
.proc ksys_snapshot_bulk_args
    php
    sei
    stx ksys_bulk_entry_lo
    sty ksys_bulk_entry_hi

    ldx active_pid

    lda ksys_bulk_entry_lo
    sta ksys_bulk_args_lo_by_pid,x
    lda ksys_bulk_entry_hi
    sta ksys_bulk_args_hi_by_pid,x

    lda proc_context,x
    sta ksys_bulk_context_by_pid,x

    plp
    cli
    clc
    rts
.endproc

; <summary>
; ksys_prepare_bulk_call copies the per-PID bulk snapshot into gate-protected
; scratch and sets io_ptr to the user argument block.
; </summary>
; <returns>A = trusted caller context.</returns>
.proc ksys_prepare_bulk_call
    ldx active_pid

    lda ksys_bulk_args_lo_by_pid,x
    sta ksys_bulk_args_lo
    sta io_ptr
    lda ksys_bulk_args_hi_by_pid,x
    sta ksys_bulk_args_hi
    sta io_ptr+1

    lda ksys_bulk_context_by_pid,x
    sta ksys_bulk_context
    rts
.endproc

; <summary>
; ksys_load_file_to_memory implements SYS_LOAD_FILE_TO_MEMORY.
; </summary>
; <param name="X/Y">Pointer to fs_load_args in the caller context.</param>
; <returns>C clear with A/X = bytes loaded; C set with Y = errno.</returns>
.proc ksys_load_file_to_memory
    jsr ksys_snapshot_bulk_args

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    jsr ksys_prepare_bulk_call
    jsr rp_fs_load_file_to_memory
    bcs @fail_release

    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_save_memory_to_file implements SYS_SAVE_MEMORY_TO_FILE.
; </summary>
; <param name="X/Y">Pointer to fs_save_args in the caller context.</param>
; <returns>C clear with A/X = bytes saved; C set with Y = errno.</returns>
.proc ksys_save_memory_to_file
    jsr ksys_snapshot_bulk_args

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    jsr ksys_prepare_bulk_call
    jsr rp_fs_save_memory_to_file
    bcs @fail_release

    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_seek implements seek(fd, signed offset32, whence) for RP filesystem
; files and writes the resulting unsigned 32-bit position into seek_args.
; </summary>
; <param name="X/Y">Pointer to a seek_args block in the caller context.</param>
; <returns>C clear with A/X = result low word; C set with Y = errno.</returns>
.proc ksys_seek
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_seek_entry_lo
    sty ksys_seek_entry_hi

    lda ksys_seek_entry_lo
    sta io_ptr
    lda ksys_seek_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_seek_entry_lo
    sta ksys_seek_args_lo_by_pid,x
    lda ksys_seek_entry_hi
    sta ksys_seek_args_hi_by_pid,x

    ldy #seek_args::fd
    lda (io_ptr),y
    sta ksys_seek_fd_by_pid,x

    ldy #seek_args::whence
    lda (io_ptr),y
    sta ksys_seek_whence_by_pid,x

    ldy #seek_args::offset_lo
    lda (io_ptr),y
    sta ksys_seek_off0_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_seek_off1_by_pid,x

    ldy #seek_args::offset_hi
    lda (io_ptr),y
    sta ksys_seek_off2_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_seek_off3_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_seek_args_lo_by_pid,x
    sta ksys_seek_args_lo
    lda ksys_seek_args_hi_by_pid,x
    sta ksys_seek_args_hi
    lda ksys_seek_fd_by_pid,x
    sta ksys_seek_fd
    lda ksys_seek_whence_by_pid,x
    sta ksys_seek_whence
    lda ksys_seek_off0_by_pid,x
    sta ksys_seek_off0
    lda ksys_seek_off1_by_pid,x
    sta ksys_seek_off1
    lda ksys_seek_off2_by_pid,x
    sta ksys_seek_off2
    lda ksys_seek_off3_by_pid,x
    sta ksys_seek_off3

    lda ksys_seek_whence
    cmp #SEEK_SET
    beq @whence_ok
    cmp #SEEK_CUR
    beq @whence_ok
    cmp #SEEK_END
    beq @whence_ok

    ldy #EINVAL
    jmp @fail_release

@whence_ok:
    ldy ksys_seek_fd
    jsr fd_resolve_file
    bcc @fd_ok

    jmp @fail_release

@fd_ok:
    ; A = RP file handle.  rp_fs_seek reads the signed 32-bit offset
    ; from io_ptr, so point io_ptr at the gate-protected offset bytes.
    pha
    lda #<ksys_seek_off0
    sta io_ptr
    lda #>ksys_seek_off0
    sta io_ptr+1
    pla
    ldy ksys_seek_whence
    jsr rp_fs_seek
    bcc @seek_ok

    jmp @fail_release

@seek_ok:
    sta ksys_seek_result0
    stx ksys_seek_result1
    lda rp_fs_result_hi_lo
    sta ksys_seek_result2
    lda rp_fs_result_hi_hi
    sta ksys_seek_result3

    ; Store the full 32-bit result into the caller's seek_args block.
    lda ksys_seek_args_lo
    sta io_ptr
    lda ksys_seek_args_hi
    sta io_ptr+1

    ldy #seek_args::result_lo
    lda ksys_seek_result0
    sta (io_ptr),y
    iny
    lda ksys_seek_result1
    sta (io_ptr),y

    ldy #seek_args::result_hi
    lda ksys_seek_result2
    sta (io_ptr),y
    iny
    lda ksys_seek_result3
    sta (io_ptr),y

    lda ksys_seek_result0
    ldx ksys_seek_result1
    pha
    phx

    jsr file_io_gate_release

    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_tell implements tell(fd) for RP filesystem files and writes the
; current unsigned 32-bit position into tell_args.
; </summary>
; <param name="X/Y">Pointer to a tell_args block in the caller context.</param>
; <returns>C clear with A/X = result low word; C set with Y = errno.</returns>
.proc ksys_tell
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_tell_entry_lo
    sty ksys_tell_entry_hi

    lda ksys_tell_entry_lo
    sta io_ptr
    lda ksys_tell_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_tell_entry_lo
    sta ksys_tell_args_lo_by_pid,x
    lda ksys_tell_entry_hi
    sta ksys_tell_args_hi_by_pid,x

    ldy #tell_args::fd
    lda (io_ptr),y
    sta ksys_tell_fd_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_tell_args_lo_by_pid,x
    sta ksys_tell_args_lo
    lda ksys_tell_args_hi_by_pid,x
    sta ksys_tell_args_hi
    lda ksys_tell_fd_by_pid,x
    sta ksys_tell_fd

    ldy ksys_tell_fd
    jsr fd_resolve_file
    bcc @fd_ok

    jmp @fail_release

@fd_ok:
    ; A = RP file handle.
    jsr rp_fs_tell
    bcc @tell_ok

    jmp @fail_release

@tell_ok:
    sta ksys_tell_result0
    stx ksys_tell_result1
    lda rp_fs_result_hi_lo
    sta ksys_tell_result2
    lda rp_fs_result_hi_hi
    sta ksys_tell_result3

    ; Store the full 32-bit result into the caller's tell_args block.
    lda ksys_tell_args_lo
    sta io_ptr
    lda ksys_tell_args_hi
    sta io_ptr+1

    ldy #tell_args::result_lo
    lda ksys_tell_result0
    sta (io_ptr),y
    iny
    lda ksys_tell_result1
    sta (io_ptr),y

    ldy #tell_args::result_hi
    lda ksys_tell_result2
    sta (io_ptr),y
    iny
    lda ksys_tell_result3
    sta (io_ptr),y

    lda ksys_tell_result0
    ldx ksys_tell_result1
    pha
    phx

    jsr file_io_gate_release

    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc



; <summary>
; ksys_delete implements delete(path, device) for RP filesystem files.
; </summary>
; <param name="X/Y">Pointer to a delete_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_delete
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_delete_entry_lo
    sty ksys_delete_entry_hi

    lda ksys_delete_entry_lo
    sta io_ptr
    lda ksys_delete_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_delete_entry_lo
    sta ksys_delete_args_lo_by_pid,x
    lda ksys_delete_entry_hi
    sta ksys_delete_args_hi_by_pid,x

    ldy #delete_args::path_ptr
    lda (io_ptr),y
    sta ksys_delete_path_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_delete_path_hi_by_pid,x

    ldy #delete_args::max_len
    lda (io_ptr),y
    sta ksys_delete_max_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_delete_max_hi_by_pid,x

    ldy #delete_args::device
    lda (io_ptr),y
    sta ksys_delete_device_by_pid,x

    ldy #delete_args::flags
    lda (io_ptr),y
    sta ksys_delete_flags_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_delete_args_lo_by_pid,x
    sta ksys_delete_args_lo
    lda ksys_delete_args_hi_by_pid,x
    sta ksys_delete_args_hi
    lda ksys_delete_path_lo_by_pid,x
    sta ksys_delete_path_lo
    lda ksys_delete_path_hi_by_pid,x
    sta ksys_delete_path_hi
    lda ksys_delete_max_lo_by_pid,x
    sta ksys_delete_max_lo
    lda ksys_delete_max_hi_by_pid,x
    sta ksys_delete_max_hi
    lda ksys_delete_device_by_pid,x
    sta ksys_delete_device
    lda ksys_delete_flags_by_pid,x
    sta ksys_delete_flags

    lda ksys_delete_flags
    cmp #FS_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_delete_path_lo
    sta io_ptr
    lda ksys_delete_path_hi
    sta io_ptr+1

    lda ksys_delete_max_lo
    ldx ksys_delete_max_hi
    ldy ksys_delete_device
    jsr rp_fs_delete
    bcc @ok

    jmp @fail_release

@ok:
    jsr file_io_gate_release
    lda #0
    tax
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_rename implements rename(old_path, new_path, device) for RP filesystem files.
; </summary>
; <param name="X/Y">Pointer to a rename_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_rename
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_rename_entry_lo
    sty ksys_rename_entry_hi

    lda ksys_rename_entry_lo
    sta io_ptr
    lda ksys_rename_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_rename_entry_lo
    sta ksys_rename_args_lo_by_pid,x
    lda ksys_rename_entry_hi
    sta ksys_rename_args_hi_by_pid,x

    ldy #rename_args::old_path_ptr
    lda (io_ptr),y
    sta ksys_rename_old_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rename_old_hi_by_pid,x

    ldy #rename_args::new_path_ptr
    lda (io_ptr),y
    sta ksys_rename_new_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rename_new_hi_by_pid,x

    ldy #rename_args::max_len
    lda (io_ptr),y
    sta ksys_rename_max_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_rename_max_hi_by_pid,x

    ldy #rename_args::device
    lda (io_ptr),y
    sta ksys_rename_device_by_pid,x

    ldy #rename_args::flags
    lda (io_ptr),y
    sta ksys_rename_flags_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_rename_args_lo_by_pid,x
    sta ksys_rename_args_lo
    lda ksys_rename_args_hi_by_pid,x
    sta ksys_rename_args_hi
    lda ksys_rename_old_lo_by_pid,x
    sta ksys_rename_old_lo
    lda ksys_rename_old_hi_by_pid,x
    sta ksys_rename_old_hi
    lda ksys_rename_new_lo_by_pid,x
    sta ksys_rename_new_lo
    lda ksys_rename_new_hi_by_pid,x
    sta ksys_rename_new_hi
    lda ksys_rename_max_lo_by_pid,x
    sta ksys_rename_max_lo
    lda ksys_rename_max_hi_by_pid,x
    sta ksys_rename_max_hi
    lda ksys_rename_device_by_pid,x
    sta ksys_rename_device
    lda ksys_rename_flags_by_pid,x
    sta ksys_rename_flags

    lda ksys_rename_flags
    cmp #FS_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    ; RP V34 rename ABI uses ARG2L for the bounded path scan length.
    ; Keep the user ABI word-shaped but reject values above 255 here.
    lda ksys_rename_max_hi
    beq @max_ok

    ldy #EINVAL
    jmp @fail_release

@max_ok:
    lda ksys_rename_new_lo
    ldx ksys_rename_new_hi
    jsr rp_fs_rename_set_new_path

    lda ksys_rename_old_lo
    sta io_ptr
    lda ksys_rename_old_hi
    sta io_ptr+1

    lda ksys_rename_max_lo
    ldy ksys_rename_device
    jsr rp_fs_rename
    bcc @ok

    jmp @fail_release

@ok:
    jsr file_io_gate_release
    lda #0
    tax
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_opendir implements opendir(path, device) for RP filesystem
; directories and attaches the resulting RP directory handle to the
; current process FD table as an OBJ_DIR.
; </summary>
; <param name="X/Y">Pointer to an opendir_args block in the caller context.</param>
; <returns>C clear with A = fd and X = 0; C set with Y = errno.</returns>
.proc ksys_opendir
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_opendir_entry_lo
    sty ksys_opendir_entry_hi

    lda ksys_opendir_entry_lo
    sta io_ptr
    lda ksys_opendir_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_opendir_entry_lo
    sta ksys_opendir_args_lo_by_pid,x
    lda ksys_opendir_entry_hi
    sta ksys_opendir_args_hi_by_pid,x

    ldy #opendir_args::path_ptr
    lda (io_ptr),y
    sta ksys_opendir_path_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_opendir_path_hi_by_pid,x

    ldy #opendir_args::max_len
    lda (io_ptr),y
    sta ksys_opendir_max_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_opendir_max_hi_by_pid,x

    ldy #opendir_args::device
    lda (io_ptr),y
    sta ksys_opendir_device_by_pid,x

    ldy #opendir_args::flags
    lda (io_ptr),y
    sta ksys_opendir_flags_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_opendir_args_lo_by_pid,x
    sta ksys_opendir_args_lo
    lda ksys_opendir_args_hi_by_pid,x
    sta ksys_opendir_args_hi
    lda ksys_opendir_path_lo_by_pid,x
    sta ksys_opendir_path_lo
    lda ksys_opendir_path_hi_by_pid,x
    sta ksys_opendir_path_hi
    lda ksys_opendir_max_lo_by_pid,x
    sta ksys_opendir_max_lo
    lda ksys_opendir_max_hi_by_pid,x
    sta ksys_opendir_max_hi
    lda ksys_opendir_device_by_pid,x
    sta ksys_opendir_device
    lda ksys_opendir_flags_by_pid,x
    sta ksys_opendir_flags

    lda ksys_opendir_flags
    cmp #FS_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    jsr fd_alloc_open
    bcc @open_obj_ok

    jmp @fail_release

@open_obj_ok:
    stx ksys_opendir_obj

    jsr fd_alloc_fd_current
    bcc @fd_ok

    ldx ksys_opendir_obj
    jsr fd_free_open
    jmp @fail_release

@fd_ok:
    sty ksys_opendir_fd

    lda ksys_opendir_path_lo
    sta io_ptr
    lda ksys_opendir_path_hi
    sta io_ptr+1

    lda ksys_opendir_max_lo
    ldx ksys_opendir_max_hi
    ldy ksys_opendir_device
    jsr rp_fs_opendir
    bcc @rp_opendir_ok

    ldx ksys_opendir_obj
    jsr fd_free_open
    jmp @fail_release

@rp_opendir_ok:
    ; A = RP directory handle.
    ldx ksys_opendir_obj
    sta open_file_handle,x

    lda #OBJ_DIR
    sta open_type,x
    lda #FD_FLAG_READ
    sta open_flags,x
    lda ksys_opendir_device
    sta open_dev,x

    ldx ksys_opendir_obj
    ldy ksys_opendir_fd
    lda #FD_FLAG_READ
    jsr fd_attach_current

    lda ksys_opendir_fd
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

; <summary>
; ksys_readdir reads the next entry from a directory fd into a caller
; supplied dir_entry buffer.
; </summary>
; <param name="X/Y">Pointer to a readdir_args block in the caller context.</param>
; <returns>C clear with A/X = 1 when an entry was returned or 0 at EOF; C set with Y = errno.</returns>
.proc ksys_readdir
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_readdir_entry_arg_lo
    sty ksys_readdir_entry_arg_hi

    lda ksys_readdir_entry_arg_lo
    sta io_ptr
    lda ksys_readdir_entry_arg_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_readdir_entry_arg_lo
    sta ksys_readdir_args_lo_by_pid,x
    lda ksys_readdir_entry_arg_hi
    sta ksys_readdir_args_hi_by_pid,x

    ldy #readdir_args::fd
    lda (io_ptr),y
    sta ksys_readdir_fd_by_pid,x

    ldy #readdir_args::entry_ptr
    lda (io_ptr),y
    sta ksys_readdir_entry_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_readdir_entry_hi_by_pid,x

    ldy #readdir_args::entry_size
    lda (io_ptr),y
    sta ksys_readdir_size_lo_by_pid,x
    iny
    lda (io_ptr),y
    sta ksys_readdir_size_hi_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_readdir_args_lo_by_pid,x
    sta ksys_readdir_args_lo
    lda ksys_readdir_args_hi_by_pid,x
    sta ksys_readdir_args_hi
    lda ksys_readdir_fd_by_pid,x
    sta ksys_readdir_fd
    lda ksys_readdir_entry_lo_by_pid,x
    sta ksys_readdir_entry_lo
    lda ksys_readdir_entry_hi_by_pid,x
    sta ksys_readdir_entry_hi
    lda ksys_readdir_size_lo_by_pid,x
    sta ksys_readdir_size_lo
    lda ksys_readdir_size_hi_by_pid,x
    sta ksys_readdir_size_hi

    ; Require destination buffer >= DIR_ENTRY_SIZE.
    lda ksys_readdir_size_hi
    bne @size_ok
    lda ksys_readdir_size_lo
    cmp #DIR_ENTRY_SIZE
    bcs @size_ok

    ldy #EINVAL
    jmp @fail_release

@size_ok:
    ldy ksys_readdir_fd
    jsr fd_resolve_dir
    bcc @fd_ok

    jmp @fail_release

@fd_ok:
    ; A = RP directory handle.
    tay
    lda ksys_readdir_entry_lo
    sta io_ptr
    lda ksys_readdir_entry_hi
    sta io_ptr+1

    lda ksys_readdir_size_lo
    ldx ksys_readdir_size_hi
    jsr rp_fs_readdir
    bcc @ok

    jmp @fail_release

@ok:
    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc

; <summary>
; ksys_closedir validates that the supplied fd is a directory fd and then
; closes it through the normal FD close path.
; </summary>
; <param name="X/Y">Pointer to a closedir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_closedir
    ; Snapshot caller argument block before any gate acquisition can yield.
    php
    sei
    stx ksys_closedir_entry_lo
    sty ksys_closedir_entry_hi

    lda ksys_closedir_entry_lo
    sta io_ptr
    lda ksys_closedir_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_closedir_entry_lo
    sta ksys_closedir_args_lo_by_pid,x
    lda ksys_closedir_entry_hi
    sta ksys_closedir_args_hi_by_pid,x

    ldy #closedir_args::fd
    lda (io_ptr),y
    sta ksys_closedir_fd_by_pid,x
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_closedir_args_lo_by_pid,x
    sta ksys_closedir_args_lo
    lda ksys_closedir_args_hi_by_pid,x
    sta ksys_closedir_args_hi
    lda ksys_closedir_fd_by_pid,x
    sta ksys_closedir_fd

    ldy ksys_closedir_fd
    jsr fd_resolve_dir
    bcc @fd_ok

    jmp @fail_release

@fd_ok:
    lda ksys_closedir_fd
    jsr fd_close
    bcc @ok

    jmp @fail_release

@ok:
    pha
    phx
    jsr file_io_gate_release
    plx
    pla
    clc
    rts

@fail_release:
    phy
    jsr file_io_gate_release
    ply
    sec
    rts
.endproc
