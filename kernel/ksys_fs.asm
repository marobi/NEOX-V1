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
.export ksys_chdir
.export ksys_getcwd
.export ksys_mkdir
.export ksys_rmdir

.import file_io_gate_acquire
.import file_io_gate_release
.import file_io_gate_phase
.import active_pid
.import proc_cwd_device
.import proc_cwd_len
.import proc_cwd_path
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
.import rp_fs_closedir
.import rp_fs_mkdir
.import rp_fs_rmdir
.import rp_fs_result_hi_lo
.import rp_fs_result_hi_hi

.importzp io_ptr
.importzp fd_ptr


.segment "BSS"

; Process/private filesystem syscall snapshot overlay.
;
; A process cannot execute two filesystem syscalls at the same time. These
; bytes must survive file_io_gate_acquire because that acquire can block/yield,
; but they do not need separate storage per syscall type. The active syscall
; interprets the same private bytes with syscall-specific aliases below.
ksys_fs_snap0:
    .res 1

ksys_fs_snap1:
    .res 1

ksys_fs_snap2:
    .res 1

ksys_fs_snap3:
    .res 1

ksys_fs_snap4:
    .res 1

ksys_fs_snap5:
    .res 1

ksys_fs_snap6:
    .res 1

ksys_fs_snap7:
    .res 1

ksys_fs_snap8:
    .res 1

ksys_fs_snap9:
    .res 1

; OPEN snapshot aliases
ksys_open_path_lo_snapshot    = ksys_fs_snap0
ksys_open_path_hi_snapshot    = ksys_fs_snap1
ksys_open_max_lo_snapshot     = ksys_fs_snap2
ksys_open_max_hi_snapshot     = ksys_fs_snap3
ksys_open_flags_snapshot      = ksys_fs_snap4
ksys_open_device_snapshot     = ksys_fs_snap5

; BULK LOAD/SAVE snapshot aliases
ksys_bulk_args_lo_snapshot    = ksys_fs_snap0
ksys_bulk_args_hi_snapshot    = ksys_fs_snap1
ksys_bulk_context_snapshot    = ksys_fs_snap2

; SEEK snapshot aliases
ksys_seek_args_lo_snapshot    = ksys_fs_snap0
ksys_seek_args_hi_snapshot    = ksys_fs_snap1
ksys_seek_fd_snapshot         = ksys_fs_snap2
ksys_seek_whence_snapshot     = ksys_fs_snap3
ksys_seek_off0_snapshot       = ksys_fs_snap4
ksys_seek_off1_snapshot       = ksys_fs_snap5
ksys_seek_off2_snapshot       = ksys_fs_snap6
ksys_seek_off3_snapshot       = ksys_fs_snap7

; TELL snapshot aliases
ksys_tell_args_lo_snapshot    = ksys_fs_snap0
ksys_tell_args_hi_snapshot    = ksys_fs_snap1
ksys_tell_fd_snapshot         = ksys_fs_snap2

; DELETE snapshot aliases
ksys_delete_args_lo_snapshot  = ksys_fs_snap0
ksys_delete_args_hi_snapshot  = ksys_fs_snap1
ksys_delete_path_lo_snapshot  = ksys_fs_snap2
ksys_delete_path_hi_snapshot  = ksys_fs_snap3
ksys_delete_max_lo_snapshot   = ksys_fs_snap4
ksys_delete_max_hi_snapshot   = ksys_fs_snap5
ksys_delete_device_snapshot   = ksys_fs_snap6
ksys_delete_flags_snapshot    = ksys_fs_snap7

; RENAME snapshot aliases
ksys_rename_args_lo_snapshot  = ksys_fs_snap0
ksys_rename_args_hi_snapshot  = ksys_fs_snap1
ksys_rename_old_lo_snapshot   = ksys_fs_snap2
ksys_rename_old_hi_snapshot   = ksys_fs_snap3
ksys_rename_new_lo_snapshot   = ksys_fs_snap4
ksys_rename_new_hi_snapshot   = ksys_fs_snap5
ksys_rename_max_lo_snapshot   = ksys_fs_snap6
ksys_rename_max_hi_snapshot   = ksys_fs_snap7
ksys_rename_device_snapshot   = ksys_fs_snap8
ksys_rename_flags_snapshot    = ksys_fs_snap9

; OPENDIR snapshot aliases
ksys_opendir_args_lo_snapshot = ksys_fs_snap0
ksys_opendir_args_hi_snapshot = ksys_fs_snap1
ksys_opendir_path_lo_snapshot = ksys_fs_snap2
ksys_opendir_path_hi_snapshot = ksys_fs_snap3
ksys_opendir_max_lo_snapshot  = ksys_fs_snap4
ksys_opendir_max_hi_snapshot  = ksys_fs_snap5
ksys_opendir_device_snapshot  = ksys_fs_snap6
ksys_opendir_flags_snapshot   = ksys_fs_snap7

; READDIR snapshot aliases
ksys_readdir_args_lo_snapshot = ksys_fs_snap0
ksys_readdir_args_hi_snapshot = ksys_fs_snap1
ksys_readdir_fd_snapshot      = ksys_fs_snap2
ksys_readdir_entry_lo_snapshot= ksys_fs_snap3
ksys_readdir_entry_hi_snapshot= ksys_fs_snap4
ksys_readdir_size_lo_snapshot = ksys_fs_snap5
ksys_readdir_size_hi_snapshot = ksys_fs_snap6

; CLOSEDIR snapshot aliases
ksys_closedir_args_lo_snapshot= ksys_fs_snap0
ksys_closedir_args_hi_snapshot= ksys_fs_snap1
ksys_closedir_fd_snapshot     = ksys_fs_snap2

; CHDIR snapshot aliases
ksys_chdir_args_lo_snapshot   = ksys_fs_snap0
ksys_chdir_args_hi_snapshot   = ksys_fs_snap1
ksys_chdir_path_lo_snapshot   = ksys_fs_snap2
ksys_chdir_path_hi_snapshot   = ksys_fs_snap3
ksys_chdir_max_lo_snapshot    = ksys_fs_snap4
ksys_chdir_max_hi_snapshot    = ksys_fs_snap5
ksys_chdir_device_snapshot    = ksys_fs_snap6
ksys_chdir_flags_snapshot     = ksys_fs_snap7

; GETCWD snapshot aliases
ksys_getcwd_args_lo_snapshot  = ksys_fs_snap0
ksys_getcwd_args_hi_snapshot  = ksys_fs_snap1
ksys_getcwd_buf_lo_snapshot   = ksys_fs_snap2
ksys_getcwd_buf_hi_snapshot   = ksys_fs_snap3
ksys_getcwd_size_lo_snapshot  = ksys_fs_snap4
ksys_getcwd_size_hi_snapshot  = ksys_fs_snap5
ksys_getcwd_flags_snapshot    = ksys_fs_snap6

; MKDIR/RMDIR snapshot aliases
ksys_mkdir_args_lo_snapshot   = ksys_fs_snap0
ksys_mkdir_args_hi_snapshot   = ksys_fs_snap1
ksys_mkdir_path_lo_snapshot   = ksys_fs_snap2
ksys_mkdir_path_hi_snapshot   = ksys_fs_snap3
ksys_mkdir_max_lo_snapshot    = ksys_fs_snap4
ksys_mkdir_max_hi_snapshot    = ksys_fs_snap5
ksys_mkdir_device_snapshot    = ksys_fs_snap6
ksys_mkdir_flags_snapshot     = ksys_fs_snap7

ksys_rmdir_args_lo_snapshot   = ksys_fs_snap0
ksys_rmdir_args_hi_snapshot   = ksys_fs_snap1
ksys_rmdir_path_lo_snapshot   = ksys_fs_snap2
ksys_rmdir_path_hi_snapshot   = ksys_fs_snap3
ksys_rmdir_max_lo_snapshot    = ksys_fs_snap4
ksys_rmdir_max_hi_snapshot    = ksys_fs_snap5
ksys_rmdir_device_snapshot    = ksys_fs_snap6
ksys_rmdir_flags_snapshot     = ksys_fs_snap7


.segment "KERN_BSS"

; V36 path resolver scratch. Valid while file_io_gate is owned.
ksys_resolved_path:
    .res NEOX_PATH_MAX

ksys_rename_old_resolved_path:
    .res NEOX_PATH_MAX

ksys_rename_old_resolved_device:
    .res 1

ksys_rename_copy_idx:
    .res 1

ksys_component_buf:
    .res 13

ksys_resolved_device:
    .res 1

ksys_resolved_len:
    .res 1

ksys_component_len:
    .res 1

ksys_resolve_src_idx:
    .res 1

ksys_resolve_max_lo:
    .res 1

ksys_resolve_max_hi:
    .res 1

ksys_chdir_entry_lo:
    .res 1

ksys_chdir_entry_hi:
    .res 1

ksys_chdir_path_lo:
    .res 1

ksys_chdir_path_hi:
    .res 1

ksys_chdir_max_lo:
    .res 1

ksys_chdir_max_hi:
    .res 1

ksys_chdir_device:
    .res 1

ksys_chdir_flags:
    .res 1

ksys_getcwd_entry_lo:
    .res 1

ksys_getcwd_entry_hi:
    .res 1

ksys_getcwd_buf_lo:
    .res 1

ksys_getcwd_buf_hi:
    .res 1

ksys_getcwd_size_lo:
    .res 1

ksys_getcwd_size_hi:
    .res 1

ksys_getcwd_flags:
    .res 1

ksys_getcwd_len:
    .res 1

ksys_cwd_len_tmp:
    .res 1

ksys_getcwd_src_idx:
    .res 1

ksys_getcwd_dst_idx:
    .res 1

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

; V37 mkdir/rmdir gate scratch aliases reuse the delete scratch because
; one filesystem syscall owns file_io_gate at a time.
ksys_mkdir_args_lo     = ksys_delete_args_lo
ksys_mkdir_args_hi     = ksys_delete_args_hi
ksys_mkdir_path_lo     = ksys_delete_path_lo
ksys_mkdir_path_hi     = ksys_delete_path_hi
ksys_mkdir_max_lo      = ksys_delete_max_lo
ksys_mkdir_max_hi      = ksys_delete_max_hi
ksys_mkdir_device      = ksys_delete_device
ksys_mkdir_flags       = ksys_delete_flags

ksys_rmdir_args_lo     = ksys_delete_args_lo
ksys_rmdir_args_hi     = ksys_delete_args_hi
ksys_rmdir_path_lo     = ksys_delete_path_lo
ksys_rmdir_path_hi     = ksys_delete_path_hi
ksys_rmdir_max_lo      = ksys_delete_max_lo
ksys_rmdir_max_hi      = ksys_delete_max_hi
ksys_rmdir_device      = ksys_delete_device
ksys_rmdir_flags       = ksys_delete_flags

.segment "KERN_TEXT"


; <summary>
; ksys_cwd_select_current loads fd_ptr with the current process/private cwd buffer.
; Root is represented by proc_cwd_len = 0.
; </summary>
; <returns>fd_ptr -> current process cwd buffer.</returns>
.proc ksys_cwd_select_current
    lda #<proc_cwd_path
    sta fd_ptr
    lda #>proc_cwd_path
    sta fd_ptr+1
    rts
.endproc

; <summary>
; ksys_resolve_clear clears the resolved path buffer.
; </summary>
; <returns>C clear.</returns>
.proc ksys_resolve_clear
    stz ksys_resolved_len
    stz ksys_resolved_path
    clc
    rts
.endproc

; <summary>
; ksys_resolve_append_char appends A to ksys_resolved_path.
; </summary>
; <returns>C clear on success; C set on path too long.</returns>
.proc ksys_resolve_append_char
    ldx ksys_resolved_len
    cpx #(NEOX_PATH_MAX - 1)
    bcc @space
    ldy #EINVAL
    sec
    rts
@space:
    sta ksys_resolved_path,x
    inx
    stx ksys_resolved_len
    stz ksys_resolved_path,x
    clc
    rts
.endproc

; <summary>
; ksys_resolve_append_slash_if_needed appends '/' between path components.
; </summary>
; <returns>C clear on success; C set on path too long.</returns>
.proc ksys_resolve_append_slash_if_needed
    lda ksys_resolved_len
    beq @done
    lda #'/'
    jsr ksys_resolve_append_char
    rts
@done:
    clc
    rts
.endproc

; <summary>
; ksys_resolve_copy_cwd copies the current process cwd component string into
; ksys_resolved_path. The cwd buffer does not include a leading slash.
; </summary>
; <returns>C clear.</returns>
.proc ksys_resolve_copy_cwd
    jsr ksys_cwd_select_current
    lda proc_cwd_device
    sta ksys_resolved_device
    stz ksys_resolved_len
    stz ksys_resolved_path
    lda proc_cwd_len
    sta ksys_cwd_len_tmp
    beq @done
    ldy #0
@loop:
    lda (fd_ptr),y
    jsr ksys_resolve_append_char
    bcs @fail
    iny
    cpy ksys_cwd_len_tmp
    bne @loop
@done:
    clc
    rts
@fail:
    sec
    rts
.endproc

; <summary>
; ksys_resolve_remove_last_component implements '..' on the resolved path.
; </summary>
; <returns>C clear.</returns>
.proc ksys_resolve_remove_last_component
    ldx ksys_resolved_len
    beq @root
@loop:
    dex
    beq @root
    lda ksys_resolved_path,x
    cmp #'/'
    bne @loop
    stx ksys_resolved_len
    stz ksys_resolved_path,x
    clc
    rts
@root:
    stz ksys_resolved_len
    stz ksys_resolved_path
    clc
    rts
.endproc

; <summary>
; ksys_resolve_commit_component appends ksys_component_buf unless it is '.'
; or '..'. Component validation is deliberately limited to syntax needed by
; the resolver; RP remains the authoritative 8.3 validator.
; </summary>
; <returns>C clear on success; C set with Y = errno.</returns>
.proc ksys_resolve_commit_component
    lda ksys_component_len
    beq @done
    cmp #1
    bne @check_parent
    lda ksys_component_buf
    cmp #'.'
    beq @done
@check_parent:
    lda ksys_component_len
    cmp #2
    bne @normal
    lda ksys_component_buf
    cmp #'.'
    bne @normal
    lda ksys_component_buf+1
    cmp #'.'
    bne @normal
    jmp ksys_resolve_remove_last_component
@normal:
    jsr ksys_resolve_append_slash_if_needed
    bcs @fail
    ldy #0
@copy:
    lda ksys_component_buf,y
    jsr ksys_resolve_append_char
    bcs @fail
    iny
    cpy ksys_component_len
    bne @copy
@done:
    clc
    rts
@fail:
    sec
    rts
.endproc

; <summary>
; ksys_resolve_path normalizes a caller path against the current process cwd.
; </summary>
; <param name="io_ptr">Caller path pointer in the current context.</param>
; <param name="A/X">Maximum bytes to scan.</param>
; <param name="Y">Legacy/default device, used only when cwd is uninitialized.</param>
; <returns>C clear, A = resolved device, io_ptr -> ksys_resolved_path; C set with Y = errno.</returns>
.proc ksys_resolve_path
    sta ksys_resolve_max_lo
    stx ksys_resolve_max_hi
    sty ksys_resolved_device

    ; Require bounded paths that fit in the V36 resolver buffer.
    lda ksys_resolve_max_hi
    beq @max_hi_ok
    ldy #EINVAL
    sec
    rts
@max_hi_ok:
    lda ksys_resolve_max_lo
    bne @max_nonzero
    jmp @bad_path
@max_nonzero:
    cmp #NEOX_PATH_MAX
    bcc @max_ok
    lda #NEOX_PATH_MAX
    sta ksys_resolve_max_lo
@max_ok:
    stz ksys_resolve_src_idx
    stz ksys_component_len

    ; Empty string is invalid.
    ldy #0
    lda (io_ptr),y
    bne @path_nonempty
    jmp @bad_path
@path_nonempty:

    ; Drive-qualified absolute path: N:/...
    cmp #'0'
    bcc @not_drive
    cmp #'4'
    bcs @not_drive
    pha
    ldy #1
    lda (io_ptr),y
    cmp #':'
    bne @not_drive_pop
    iny
    lda (io_ptr),y
    cmp #'/'
    bne @not_drive_pop
    pla
    sec
    sbc #'0'
    sta ksys_resolved_device
    jsr ksys_resolve_clear
    lda #3
    sta ksys_resolve_src_idx
    bra @parse_loop
@not_drive_pop:
    pla
@not_drive:
    ; Absolute path on current device.
    ldy #0
    lda (io_ptr),y
    cmp #'/'
    bne @relative
    jsr ksys_cwd_select_current
    lda proc_cwd_device
    sta ksys_resolved_device
    jsr ksys_resolve_clear
    lda #1
    sta ksys_resolve_src_idx
    bra @parse_loop
@relative:
    jsr ksys_resolve_copy_cwd
    bcs @fail

@parse_loop:
    ldy ksys_resolve_src_idx
    cpy ksys_resolve_max_lo
    bcs @bad_path
    lda (io_ptr),y
    beq @finish
    cmp #'/'
    beq @separator

    ldx ksys_component_len
    cpx #12
    bcc @component_space
    ldy #EINVAL
    sec
    rts
@component_space:
    sta ksys_component_buf,x
    inx
    stx ksys_component_len
    inc ksys_resolve_src_idx
    bra @parse_loop

@separator:
    jsr ksys_resolve_commit_component
    bcs @fail
    stz ksys_component_len
    inc ksys_resolve_src_idx
    bra @parse_loop

@finish:
    jsr ksys_resolve_commit_component
    bcs @fail
    lda ksys_resolved_len
    bne @non_root
    lda #'/'
    sta ksys_resolved_path
    stz ksys_resolved_path+1
    lda #1
    sta ksys_resolved_len
@non_root:
    lda #<ksys_resolved_path
    sta io_ptr
    lda #>ksys_resolved_path
    sta io_ptr+1
    lda ksys_resolved_device
    clc
    rts

@bad_path:
    ldy #EINVAL
@fail:
    sec
    rts
.endproc

; <summary>
; ksys_set_cwd_from_resolved stores ksys_resolved_path as current cwd for
; active_pid. Root '/' is stored internally as an empty path.
; </summary>
; <returns>C clear.</returns>
.proc ksys_set_cwd_from_resolved
    jsr ksys_cwd_select_current
    lda ksys_resolved_device
    sta proc_cwd_device

    lda ksys_resolved_len
    cmp #1
    bne @copy_path
    lda ksys_resolved_path
    cmp #'/'
    bne @copy_path
    stz proc_cwd_len
    ldy #0
    lda #0
    sta (fd_ptr),y
    clc
    rts

@copy_path:
    lda ksys_resolved_len
    sta proc_cwd_len
    sta ksys_cwd_len_tmp
    ldy #0
@loop:
    lda ksys_resolved_path,y
    sta (fd_ptr),y
    iny
    cpy ksys_cwd_len_tmp
    bne @loop
    lda #0
    sta (fd_ptr),y
    clc
    rts
.endproc

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
    sta ksys_open_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_open_path_hi_snapshot

    ldy #open_args::max_len
    lda (io_ptr),y
    sta ksys_open_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_open_max_hi_snapshot

    ldy #open_args::flags
    lda (io_ptr),y
    sta ksys_open_flags_snapshot

    ldy #open_args::device
    lda (io_ptr),y
    sta ksys_open_device_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ; Copy process/private snapshot into gate-protected scratch.
    ldx active_pid
    lda ksys_open_path_lo_snapshot
    sta ksys_open_path_lo
    lda ksys_open_path_hi_snapshot
    sta ksys_open_path_hi
    lda ksys_open_max_lo_snapshot
    sta ksys_open_max_lo
    lda ksys_open_max_hi_snapshot
    sta ksys_open_max_hi
    lda ksys_open_flags_snapshot
    sta ksys_open_flags
    lda ksys_open_device_snapshot
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
    lda ksys_open_path_lo
    sta io_ptr
    lda ksys_open_path_hi
    sta io_ptr+1
    lda ksys_open_max_lo
    ldx ksys_open_max_hi
    ldy ksys_open_device
    jsr ksys_resolve_path
    bcc @open_path_ok

    jmp @fail_release

@open_path_ok:
    sta ksys_open_device
    lda #<ksys_resolved_path
    sta ksys_open_path_lo
    lda #>ksys_resolved_path
    sta ksys_open_path_hi
    lda #<NEOX_PATH_MAX
    sta ksys_open_max_lo
    lda #>NEOX_PATH_MAX
    sta ksys_open_max_hi

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
    sta ksys_bulk_args_lo_snapshot
    lda ksys_bulk_entry_hi
    sta ksys_bulk_args_hi_snapshot

    lda proc_context,x
    sta ksys_bulk_context_snapshot

    plp
    cli
    clc
    rts
.endproc

; <summary>
; ksys_prepare_bulk_call copies the process/private bulk snapshot into gate-protected
; scratch and sets io_ptr to the user argument block.
; </summary>
; <returns>A = trusted caller context.</returns>
.proc ksys_prepare_bulk_call
    ldx active_pid

    lda ksys_bulk_args_lo_snapshot
    sta ksys_bulk_args_lo
    sta io_ptr
    lda ksys_bulk_args_hi_snapshot
    sta ksys_bulk_args_hi
    sta io_ptr+1

    lda ksys_bulk_context_snapshot
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
    sta ksys_seek_args_lo_snapshot
    lda ksys_seek_entry_hi
    sta ksys_seek_args_hi_snapshot

    ldy #seek_args::fd
    lda (io_ptr),y
    sta ksys_seek_fd_snapshot

    ldy #seek_args::whence
    lda (io_ptr),y
    sta ksys_seek_whence_snapshot

    ldy #seek_args::offset_lo
    lda (io_ptr),y
    sta ksys_seek_off0_snapshot
    iny
    lda (io_ptr),y
    sta ksys_seek_off1_snapshot

    ldy #seek_args::offset_hi
    lda (io_ptr),y
    sta ksys_seek_off2_snapshot
    iny
    lda (io_ptr),y
    sta ksys_seek_off3_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_seek_args_lo_snapshot
    sta ksys_seek_args_lo
    lda ksys_seek_args_hi_snapshot
    sta ksys_seek_args_hi
    lda ksys_seek_fd_snapshot
    sta ksys_seek_fd
    lda ksys_seek_whence_snapshot
    sta ksys_seek_whence
    lda ksys_seek_off0_snapshot
    sta ksys_seek_off0
    lda ksys_seek_off1_snapshot
    sta ksys_seek_off1
    lda ksys_seek_off2_snapshot
    sta ksys_seek_off2
    lda ksys_seek_off3_snapshot
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
    sta ksys_tell_args_lo_snapshot
    lda ksys_tell_entry_hi
    sta ksys_tell_args_hi_snapshot

    ldy #tell_args::fd
    lda (io_ptr),y
    sta ksys_tell_fd_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_tell_args_lo_snapshot
    sta ksys_tell_args_lo
    lda ksys_tell_args_hi_snapshot
    sta ksys_tell_args_hi
    lda ksys_tell_fd_snapshot
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
; ksys_rename_copy_resolved_old snapshots the currently resolved old rename path
; before resolving the new rename path into the shared resolver buffer.
; </summary>
; <returns>C clear on success; C set with Y = errno on overflow.</returns>
.proc ksys_rename_copy_resolved_old
    stz ksys_rename_copy_idx
@loop:
    ldy ksys_rename_copy_idx
    cpy #NEOX_PATH_MAX
    bcc @in_range

    ldy #EINVAL
    sec
    rts

@in_range:
    lda ksys_resolved_path,y
    sta ksys_rename_old_resolved_path,y
    beq @done

    inc ksys_rename_copy_idx
    bra @loop

@done:
    clc
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
    sta ksys_delete_args_lo_snapshot
    lda ksys_delete_entry_hi
    sta ksys_delete_args_hi_snapshot

    ldy #delete_args::path_ptr
    lda (io_ptr),y
    sta ksys_delete_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_delete_path_hi_snapshot

    ldy #delete_args::max_len
    lda (io_ptr),y
    sta ksys_delete_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_delete_max_hi_snapshot

    ldy #delete_args::device
    lda (io_ptr),y
    sta ksys_delete_device_snapshot

    ldy #delete_args::flags
    lda (io_ptr),y
    sta ksys_delete_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_delete_args_lo_snapshot
    sta ksys_delete_args_lo
    lda ksys_delete_args_hi_snapshot
    sta ksys_delete_args_hi
    lda ksys_delete_path_lo_snapshot
    sta ksys_delete_path_lo
    lda ksys_delete_path_hi_snapshot
    sta ksys_delete_path_hi
    lda ksys_delete_max_lo_snapshot
    sta ksys_delete_max_lo
    lda ksys_delete_max_hi_snapshot
    sta ksys_delete_max_hi
    lda ksys_delete_device_snapshot
    sta ksys_delete_device
    lda ksys_delete_flags_snapshot
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
    jsr ksys_resolve_path
    bcc @path_ok

    jmp @fail_release

@path_ok:
    sta ksys_delete_device
    lda #<ksys_resolved_path
    sta io_ptr
    lda #>ksys_resolved_path
    sta io_ptr+1
    lda #<NEOX_PATH_MAX
    ldx #>NEOX_PATH_MAX
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
    sta ksys_rename_args_lo_snapshot
    lda ksys_rename_entry_hi
    sta ksys_rename_args_hi_snapshot

    ldy #rename_args::old_path_ptr
    lda (io_ptr),y
    sta ksys_rename_old_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_rename_old_hi_snapshot

    ldy #rename_args::new_path_ptr
    lda (io_ptr),y
    sta ksys_rename_new_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_rename_new_hi_snapshot

    ldy #rename_args::max_len
    lda (io_ptr),y
    sta ksys_rename_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_rename_max_hi_snapshot

    ldy #rename_args::device
    lda (io_ptr),y
    sta ksys_rename_device_snapshot

    ldy #rename_args::flags
    lda (io_ptr),y
    sta ksys_rename_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_rename_args_lo_snapshot
    sta ksys_rename_args_lo
    lda ksys_rename_args_hi_snapshot
    sta ksys_rename_args_hi
    lda ksys_rename_old_lo_snapshot
    sta ksys_rename_old_lo
    lda ksys_rename_old_hi_snapshot
    sta ksys_rename_old_hi
    lda ksys_rename_new_lo_snapshot
    sta ksys_rename_new_lo
    lda ksys_rename_new_hi_snapshot
    sta ksys_rename_new_hi
    lda ksys_rename_max_lo_snapshot
    sta ksys_rename_max_lo
    lda ksys_rename_max_hi_snapshot
    sta ksys_rename_max_hi
    lda ksys_rename_device_snapshot
    sta ksys_rename_device
    lda ksys_rename_flags_snapshot
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
    lda ksys_rename_old_lo
    sta io_ptr
    lda ksys_rename_old_hi
    sta io_ptr+1
    lda ksys_rename_max_lo
    ldx ksys_rename_max_hi
    ldy ksys_rename_device
    jsr ksys_resolve_path
    bcc @old_path_ok

    jmp @fail_release

@old_path_ok:
    sta ksys_rename_old_resolved_device
    jsr ksys_rename_copy_resolved_old
    bcc @old_copied

    jmp @fail_release

@old_copied:
    lda ksys_rename_new_lo
    sta io_ptr
    lda ksys_rename_new_hi
    sta io_ptr+1
    lda ksys_rename_max_lo
    ldx ksys_rename_max_hi
    ldy ksys_rename_device
    jsr ksys_resolve_path
    bcc @new_path_ok

    jmp @fail_release

@new_path_ok:
    cmp ksys_rename_old_resolved_device
    beq @same_device

    ldy #EINVAL
    jmp @fail_release

@same_device:
    lda #<ksys_resolved_path
    ldx #>ksys_resolved_path
    jsr rp_fs_rename_set_new_path

    lda #<ksys_rename_old_resolved_path
    sta io_ptr
    lda #>ksys_rename_old_resolved_path
    sta io_ptr+1

    lda #<NEOX_PATH_MAX
    ldy ksys_rename_old_resolved_device
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
    sta ksys_opendir_args_lo_snapshot
    lda ksys_opendir_entry_hi
    sta ksys_opendir_args_hi_snapshot

    ldy #opendir_args::path_ptr
    lda (io_ptr),y
    sta ksys_opendir_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_opendir_path_hi_snapshot

    ldy #opendir_args::max_len
    lda (io_ptr),y
    sta ksys_opendir_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_opendir_max_hi_snapshot

    ldy #opendir_args::device
    lda (io_ptr),y
    sta ksys_opendir_device_snapshot

    ldy #opendir_args::flags
    lda (io_ptr),y
    sta ksys_opendir_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_opendir_args_lo_snapshot
    sta ksys_opendir_args_lo
    lda ksys_opendir_args_hi_snapshot
    sta ksys_opendir_args_hi
    lda ksys_opendir_path_lo_snapshot
    sta ksys_opendir_path_lo
    lda ksys_opendir_path_hi_snapshot
    sta ksys_opendir_path_hi
    lda ksys_opendir_max_lo_snapshot
    sta ksys_opendir_max_lo
    lda ksys_opendir_max_hi_snapshot
    sta ksys_opendir_max_hi
    lda ksys_opendir_device_snapshot
    sta ksys_opendir_device
    lda ksys_opendir_flags_snapshot
    sta ksys_opendir_flags

    lda ksys_opendir_flags
    cmp #FS_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_opendir_path_lo
    sta io_ptr
    lda ksys_opendir_path_hi
    sta io_ptr+1
    lda ksys_opendir_max_lo
    ldx ksys_opendir_max_hi
    ldy ksys_opendir_device
    jsr ksys_resolve_path
    bcc @opendir_path_ok

    jmp @fail_release

@opendir_path_ok:
    sta ksys_opendir_device
    lda #<ksys_resolved_path
    sta ksys_opendir_path_lo
    lda #>ksys_resolved_path
    sta ksys_opendir_path_hi
    lda #<NEOX_PATH_MAX
    sta ksys_opendir_max_lo
    lda #>NEOX_PATH_MAX
    sta ksys_opendir_max_hi

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
    sta ksys_readdir_args_lo_snapshot
    lda ksys_readdir_entry_arg_hi
    sta ksys_readdir_args_hi_snapshot

    ldy #readdir_args::fd
    lda (io_ptr),y
    sta ksys_readdir_fd_snapshot

    ldy #readdir_args::entry_ptr
    lda (io_ptr),y
    sta ksys_readdir_entry_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_readdir_entry_hi_snapshot

    ldy #readdir_args::entry_size
    lda (io_ptr),y
    sta ksys_readdir_size_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_readdir_size_hi_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_readdir_args_lo_snapshot
    sta ksys_readdir_args_lo
    lda ksys_readdir_args_hi_snapshot
    sta ksys_readdir_args_hi
    lda ksys_readdir_fd_snapshot
    sta ksys_readdir_fd
    lda ksys_readdir_entry_lo_snapshot
    sta ksys_readdir_entry_lo
    lda ksys_readdir_entry_hi_snapshot
    sta ksys_readdir_entry_hi
    lda ksys_readdir_size_lo_snapshot
    sta ksys_readdir_size_lo
    lda ksys_readdir_size_hi_snapshot
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
    sta ksys_closedir_args_lo_snapshot
    lda ksys_closedir_entry_hi
    sta ksys_closedir_args_hi_snapshot

    ldy #closedir_args::fd
    lda (io_ptr),y
    sta ksys_closedir_fd_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid

    lda ksys_closedir_args_lo_snapshot
    sta ksys_closedir_args_lo
    lda ksys_closedir_args_hi_snapshot
    sta ksys_closedir_args_hi
    lda ksys_closedir_fd_snapshot
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
; <summary>
; ksys_chdir changes the current process cwd after validating the resolved
; directory with RP OPENDIR/CLOSEDIR. No RP global cwd is modified.
; </summary>
; <param name="X/Y">Pointer to a chdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_chdir
    php
    sei
    stx ksys_chdir_entry_lo
    sty ksys_chdir_entry_hi

    lda ksys_chdir_entry_lo
    sta io_ptr
    lda ksys_chdir_entry_hi
    sta io_ptr+1

    ldx active_pid

    ldy #chdir_args::path_ptr
    lda (io_ptr),y
    sta ksys_chdir_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_chdir_path_hi_snapshot

    ldy #chdir_args::max_len
    lda (io_ptr),y
    sta ksys_chdir_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_chdir_max_hi_snapshot

    ldy #chdir_args::device
    lda (io_ptr),y
    sta ksys_chdir_device_snapshot

    ldy #chdir_args::flags
    lda (io_ptr),y
    sta ksys_chdir_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid
    lda ksys_chdir_path_lo_snapshot
    sta ksys_chdir_path_lo
    lda ksys_chdir_path_hi_snapshot
    sta ksys_chdir_path_hi
    lda ksys_chdir_max_lo_snapshot
    sta ksys_chdir_max_lo
    lda ksys_chdir_max_hi_snapshot
    sta ksys_chdir_max_hi
    lda ksys_chdir_device_snapshot
    sta ksys_chdir_device
    lda ksys_chdir_flags_snapshot
    sta ksys_chdir_flags

    lda ksys_chdir_flags
    cmp #NEOX_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_chdir_path_lo
    sta io_ptr
    lda ksys_chdir_path_hi
    sta io_ptr+1
    lda ksys_chdir_max_lo
    ldx ksys_chdir_max_hi
    ldy ksys_chdir_device
    jsr ksys_resolve_path
    bcc @path_ok

    jmp @fail_release

@path_ok:
    sta ksys_chdir_device
    lda #<NEOX_PATH_MAX
    ldx #>NEOX_PATH_MAX
    ldy ksys_chdir_device
    jsr rp_fs_opendir
    bcc @opendir_ok

    jmp @fail_release

@opendir_ok:
    pha
    jsr rp_fs_closedir
    pla
    bcc @close_ok

    jmp @fail_release

@close_ok:
    jsr ksys_set_cwd_from_resolved
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
; ksys_mkdir creates a directory after resolving the caller path against the
; current process cwd. RP receives only an explicit resolved path and device.
; </summary>
; <param name="X/Y">Pointer to a mkdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_mkdir
    php
    sei
    stx ksys_mkdir_args_lo_snapshot
    sty ksys_mkdir_args_hi_snapshot

    lda ksys_mkdir_args_lo_snapshot
    sta io_ptr
    lda ksys_mkdir_args_hi_snapshot
    sta io_ptr+1

    ldy #mkdir_args::path_ptr
    lda (io_ptr),y
    sta ksys_mkdir_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_mkdir_path_hi_snapshot

    ldy #mkdir_args::max_len
    lda (io_ptr),y
    sta ksys_mkdir_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_mkdir_max_hi_snapshot

    ldy #mkdir_args::device
    lda (io_ptr),y
    sta ksys_mkdir_device_snapshot

    ldy #mkdir_args::flags
    lda (io_ptr),y
    sta ksys_mkdir_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda ksys_mkdir_path_lo_snapshot
    sta ksys_mkdir_path_lo
    lda ksys_mkdir_path_hi_snapshot
    sta ksys_mkdir_path_hi
    lda ksys_mkdir_max_lo_snapshot
    sta ksys_mkdir_max_lo
    lda ksys_mkdir_max_hi_snapshot
    sta ksys_mkdir_max_hi
    lda ksys_mkdir_device_snapshot
    sta ksys_mkdir_device
    lda ksys_mkdir_flags_snapshot
    sta ksys_mkdir_flags

    lda ksys_mkdir_flags
    cmp #NEOX_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_mkdir_path_lo
    sta io_ptr
    lda ksys_mkdir_path_hi
    sta io_ptr+1
    lda ksys_mkdir_max_lo
    ldx ksys_mkdir_max_hi
    ldy ksys_mkdir_device
    jsr ksys_resolve_path
    bcc @path_ok

    jmp @fail_release

@path_ok:
    sta ksys_mkdir_device
    lda #<ksys_resolved_path
    sta io_ptr
    lda #>ksys_resolved_path
    sta io_ptr+1
    lda #<NEOX_PATH_MAX
    ldx #>NEOX_PATH_MAX
    ldy ksys_mkdir_device
    jsr rp_fs_mkdir
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
; ksys_rmdir removes an empty directory after resolving the caller path against
; the current process cwd. RP receives only an explicit resolved path and device.
; </summary>
; <param name="X/Y">Pointer to a rmdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_rmdir
    php
    sei
    stx ksys_rmdir_args_lo_snapshot
    sty ksys_rmdir_args_hi_snapshot

    lda ksys_rmdir_args_lo_snapshot
    sta io_ptr
    lda ksys_rmdir_args_hi_snapshot
    sta io_ptr+1

    ldy #rmdir_args::path_ptr
    lda (io_ptr),y
    sta ksys_rmdir_path_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_rmdir_path_hi_snapshot

    ldy #rmdir_args::max_len
    lda (io_ptr),y
    sta ksys_rmdir_max_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_rmdir_max_hi_snapshot

    ldy #rmdir_args::device
    lda (io_ptr),y
    sta ksys_rmdir_device_snapshot

    ldy #rmdir_args::flags
    lda (io_ptr),y
    sta ksys_rmdir_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    lda ksys_rmdir_path_lo_snapshot
    sta ksys_rmdir_path_lo
    lda ksys_rmdir_path_hi_snapshot
    sta ksys_rmdir_path_hi
    lda ksys_rmdir_max_lo_snapshot
    sta ksys_rmdir_max_lo
    lda ksys_rmdir_max_hi_snapshot
    sta ksys_rmdir_max_hi
    lda ksys_rmdir_device_snapshot
    sta ksys_rmdir_device
    lda ksys_rmdir_flags_snapshot
    sta ksys_rmdir_flags

    lda ksys_rmdir_flags
    cmp #NEOX_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_rmdir_path_lo
    sta io_ptr
    lda ksys_rmdir_path_hi
    sta io_ptr+1
    lda ksys_rmdir_max_lo
    ldx ksys_rmdir_max_hi
    ldy ksys_rmdir_device
    jsr ksys_resolve_path
    bcc @path_ok

    jmp @fail_release

@path_ok:
    sta ksys_rmdir_device
    lda #<ksys_resolved_path
    sta io_ptr
    lda #>ksys_resolved_path
    sta io_ptr+1
    lda #<NEOX_PATH_MAX
    ldx #>NEOX_PATH_MAX
    ldy ksys_rmdir_device
    jsr rp_fs_rmdir
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
; ksys_getcwd copies the current process cwd as D:/PATH into a caller buffer.
; </summary>
; <param name="X/Y">Pointer to a getcwd_args block in the caller context.</param>
; <returns>C clear with A = result length and X = 0; C set with Y = errno.</returns>
.proc ksys_getcwd
    php
    sei
    stx ksys_getcwd_entry_lo
    sty ksys_getcwd_entry_hi

    lda ksys_getcwd_entry_lo
    sta io_ptr
    lda ksys_getcwd_entry_hi
    sta io_ptr+1

    ldx active_pid

    lda ksys_getcwd_entry_lo
    sta ksys_getcwd_args_lo_snapshot
    lda ksys_getcwd_entry_hi
    sta ksys_getcwd_args_hi_snapshot

    ldy #getcwd_args::buffer_ptr
    lda (io_ptr),y
    sta ksys_getcwd_buf_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_getcwd_buf_hi_snapshot

    ldy #getcwd_args::buffer_size
    lda (io_ptr),y
    sta ksys_getcwd_size_lo_snapshot
    iny
    lda (io_ptr),y
    sta ksys_getcwd_size_hi_snapshot

    ldy #getcwd_args::flags
    lda (io_ptr),y
    sta ksys_getcwd_flags_snapshot
    plp
    cli

    jsr file_io_gate_acquire
    bcs @gate_acquired

    ldy #EINVAL
    sec
    rts

@gate_acquired:
    ldx active_pid
    lda ksys_getcwd_args_lo_snapshot
    sta ksys_getcwd_entry_lo
    lda ksys_getcwd_args_hi_snapshot
    sta ksys_getcwd_entry_hi
    lda ksys_getcwd_buf_lo_snapshot
    sta ksys_getcwd_buf_lo
    lda ksys_getcwd_buf_hi_snapshot
    sta ksys_getcwd_buf_hi
    lda ksys_getcwd_size_lo_snapshot
    sta ksys_getcwd_size_lo
    lda ksys_getcwd_size_hi_snapshot
    sta ksys_getcwd_size_hi
    lda ksys_getcwd_flags_snapshot
    sta ksys_getcwd_flags

    lda ksys_getcwd_flags
    cmp #NEOX_PATH_FLAGS_NONE
    beq @flags_ok

    ldy #EINVAL
    jmp @fail_release

@flags_ok:
    lda ksys_getcwd_size_hi
    bne @size_large
    lda ksys_getcwd_size_lo
    cmp #4
    bcs @size_min_ok
    ldy #EINVAL
    jmp @fail_release
@size_large:
@size_min_ok:
    jsr ksys_cwd_select_current

    ; Required length excluding NUL = 3 + proc_cwd_len.
    lda proc_cwd_len
    clc
    adc #3
    sta ksys_getcwd_len

    ; Need buffer size >= length + 1.
    clc
    adc #1
    sta ksys_component_len
    lda ksys_getcwd_size_hi
    bne @buffer_ok
    lda ksys_getcwd_size_lo
    cmp ksys_component_len
    bcs @buffer_ok
    ldy #EINVAL
    jmp @fail_release

@buffer_ok:
    lda ksys_getcwd_buf_lo
    sta io_ptr
    lda ksys_getcwd_buf_hi
    sta io_ptr+1

    ldy #0
    lda proc_cwd_device
    clc
    adc #'0'
    sta (io_ptr),y
    iny
    lda #':'
    sta (io_ptr),y
    iny
    lda #'/'
    sta (io_ptr),y
    iny

    lda proc_cwd_len
    sta ksys_cwd_len_tmp
    beq @terminate

    stz ksys_getcwd_src_idx
    lda #3
    sta ksys_getcwd_dst_idx
@copy_cwd:
    ldy ksys_getcwd_src_idx
    lda (fd_ptr),y
    ldy ksys_getcwd_dst_idx
    sta (io_ptr),y
    inc ksys_getcwd_src_idx
    inc ksys_getcwd_dst_idx
    lda ksys_getcwd_src_idx
    cmp ksys_cwd_len_tmp
    bne @copy_cwd

@terminate:
    ldy ksys_getcwd_len
    lda #0
    sta (io_ptr),y

    ; Store result_len in the caller argument block.
    lda ksys_getcwd_entry_lo
    sta io_ptr
    lda ksys_getcwd_entry_hi
    sta io_ptr+1
    ldy #getcwd_args::result_len
    lda ksys_getcwd_len
    sta (io_ptr),y
    iny
    lda #0
    sta (io_ptr),y

    jsr file_io_gate_release
    lda ksys_getcwd_len
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

