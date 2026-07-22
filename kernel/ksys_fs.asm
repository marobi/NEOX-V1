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
.include "mailbox.inc"
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

.import rp_fs_exec

.importzp io_ptr
.importzp dev_ptr


.segment "BSS"

; Process-private argument pointer snapshot.
;
; file_io_gate_acquire may block and yield, so ksys_fs_begin preserves the
; caller argument-block pointer in the process context before acquiring FILE_IO.
ksys_fs_snap0:
    .res 1

ksys_fs_snap1:
    .res 1


.segment "KERN_BSS"

; Shared open/opendir transaction scratch. FILE_IO remains owned while these
; values are live, including across WAIT_RP.
ksys_open_device:
    .res 1

ksys_open_obj:
    .res 1

ksys_open_fd:
    .res 1

; Current no-handle filesystem operation while FILE_IO is owned.
ksys_fs_operation:
    .res 1


.segment "KERN_TEXT"


; <summary>
; ksys_fs_begin saves the caller argument-block pointer in process-private
; storage, acquires FILE_IO, and restores io_ptr after a possible wait.
; </summary>
; <param name="X/Y">Caller argument-block pointer.</param>
; <returns>C set when FILE_IO is owned; C clear with Y=EINVAL on failure.</returns>
.proc ksys_fs_begin
    stx ksys_fs_snap0
    sty ksys_fs_snap1
    jsr file_io_gate_acquire
    bcs @owned
    ldy #EINVAL
    clc
    rts
@owned:
    lda ksys_fs_snap0
    sta io_ptr
    lda ksys_fs_snap1
    sta io_ptr+1
    sec
    rts
.endproc

; <summary>
; ksys_fs_finish releases FILE_IO while preserving A, X, Y, and status.
; </summary>
.proc ksys_fs_finish
    php
    pha
    phx
    phy
    jsr file_io_gate_release
    ply
    plx
    pla
    plp
    rts
.endproc

; <summary>
; Converts one caller pathname to uppercase ASCII in place.
;
; This is filesystem policy, not command parsing. Generic argument buffers
; remain byte-preserving until a pathname-bearing filesystem syscall is made.
; dev_ptr is shared zero-page scratch and is safe here because FILE_IO is
; owned for the complete normalization and RP transaction.
; </summary>
; <param name="Y">Offset of the pathname pointer inside the syscall block.</param>
; <returns>C clear on success.</returns>
.proc ksys_fs_uppercase_path_at_y
    lda (io_ptr),y
    sta dev_ptr
    iny
    lda (io_ptr),y
    sta dev_ptr+1

    ldy #0
@loop:
    lda (dev_ptr),y
    beq @done

    cmp #'a'
    bcc @next
    cmp #'z' + 1
    bcs @next

    sec
    sbc #$20
    sta (dev_ptr),y

@next:
    iny
    bne @loop

    ; A pathname without a terminator in the first 256 bytes is invalid.
    ldy #EINVAL
    sec
    rts

@done:
    clc
    rts
.endproc

; <summary>
; Applies pathname normalization required by a no-handle filesystem operation.
; </summary>
; <param name="A">RP_FS_OP_* operation code.</param>
; <returns>C clear on success; C set with Y=errno on failure.</returns>
.proc ksys_fs_normalize_no_handle_paths
    cmp #RP_FS_OP_GETCWD
    beq @none
    cmp #RP_FS_OP_RENAME
    beq @rename

    ; LOAD, SAVE, DELETE, CHDIR, MKDIR, and RMDIR all place their first
    ; pathname pointer at byte zero of the syscall argument block.
    ldy #0
    jmp ksys_fs_uppercase_path_at_y

@rename:
    ldy #rename_args::old_path_ptr
    jsr ksys_fs_uppercase_path_at_y
    bcs @fail

    ldy #rename_args::new_path_ptr
    jmp ksys_fs_uppercase_path_at_y

@none:
    clc
@fail:
    rts
.endproc

; <summary>
; Executes a path/bulk filesystem operation that needs no trusted RP handle.
; </summary>
; <param name="A">RP_FS_OP_* operation.</param>
; <param name="X/Y">Caller argument-block pointer.</param>
; <returns>The generic filesystem result.</returns>
.proc ksys_fs_exec_no_handle
    pha
    jsr ksys_fs_begin
    bcs @owned

    pla
    sec
    rts

@owned:
    pla
    sta ksys_fs_operation

    jsr ksys_fs_normalize_no_handle_paths
    bcc @normalized
    jmp ksys_fs_finish

@normalized:
    lda ksys_fs_operation
    ldx #$FF
    ldy #$00
    jsr rp_fs_exec
    jmp ksys_fs_finish
.endproc

; <summary>
; Executes a file-handle operation whose fd is byte zero of the argument block.
; </summary>
; <param name="A">RP_FS_OP_SEEK or RP_FS_OP_TELL.</param>
; <param name="X/Y">Caller argument-block pointer.</param>
; <returns>The generic filesystem result.</returns>
.proc ksys_fs_exec_file_handle
    pha
    jsr ksys_fs_begin
    bcs @owned

    pla
    sec
    rts

@owned:
    ldy #$00
    lda (io_ptr),y
    tay
    jsr fd_resolve_file
    bcs @resolve_fail

    tax
    pla
    ldy #$00
    jsr rp_fs_exec
    jmp ksys_fs_finish

@resolve_fail:
    pla
    jmp ksys_fs_finish
.endproc

; <summary>
; ksys_open implements open(path, mode, device) for RP filesystem files
; and attaches the resulting RP handle to the current process FD table.
; </summary>
; <param name="X/Y">Pointer to an open_args block in the caller context.</param>
; <returns>C clear with A = fd and X = 0; C set with Y = errno.</returns>
.proc ksys_open
    jsr ksys_fs_begin
    bcs @gate_owned
    sec
    rts
@gate_owned:
    ldy #open_args::path_ptr
    jsr ksys_fs_uppercase_path_at_y
    bcc @path_ready
    jmp @fail

@path_ready:
    ldy #open_args::flags
    lda (io_ptr),y
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
    jmp @fail
@flags_ok:
    jsr fd_alloc_open
    bcc @open_obj_ok
    jmp @fail
@open_obj_ok:
    stx ksys_open_obj
    jsr fd_alloc_fd_current
    bcc @fd_ok
    ldx ksys_open_obj
    jsr fd_free_open
    jmp @fail
@fd_ok:
    sty ksys_open_fd
    lda #RP_FS_OP_OPEN
    ldx #$FF
    ldy #0
    jsr rp_fs_exec
    bcc @rp_ok
    phy
    ldx ksys_open_obj
    jsr fd_free_open
    ply
    jmp @fail
@rp_ok:
    ; A = RP handle; Y = resolved device returned in RP_FLAGS.
    sty ksys_open_device
    ldx ksys_open_obj
    sta open_file_handle,x
    lda #OBJ_FILE
    sta open_type,x
    ldy #open_args::flags
    lda (io_ptr),y
    cmp #OPEN_READ
    beq @read_flags
    cmp #OPEN_WRITE_TRUNC
    beq @write_flags
    cmp #OPEN_WRITE_EXISTING
    beq @write_flags
    lda #(FD_FLAG_READ | FD_FLAG_WRITE)
    bra @store_flags
@read_flags:
    lda #FD_FLAG_READ
    bra @store_flags
@write_flags:
    lda #FD_FLAG_WRITE
@store_flags:
    sta open_flags,x
    lda ksys_open_device
    sta open_dev,x
    ldy ksys_open_fd
    lda open_flags,x
    jsr fd_attach_current
    lda ksys_open_fd
    ldx #0
    clc
    jmp ksys_fs_finish
@fail:
    sec
    jmp ksys_fs_finish
.endproc

; <summary>
; ksys_load_file_to_memory implements SYS_LOAD_FILE_TO_MEMORY.
; </summary>
; <param name="X/Y">Pointer to fs_load_args in the caller context.</param>
; <returns>C clear with A/X = bytes loaded; C set with Y = errno.</returns>
.proc ksys_load_file_to_memory
    lda #RP_FS_OP_LOAD
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_save_memory_to_file implements SYS_SAVE_MEMORY_TO_FILE.
; </summary>
; <param name="X/Y">Pointer to fs_save_args in the caller context.</param>
; <returns>C clear with A/X = bytes saved; C set with Y = errno.</returns>
.proc ksys_save_memory_to_file
    lda #RP_FS_OP_SAVE
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_seek implements seek(fd, signed offset32, whence) for RP filesystem
; files and writes the resulting unsigned 32-bit position into seek_args.
; </summary>
; <param name="X/Y">Pointer to a seek_args block in the caller context.</param>
; <returns>C clear with A/X = result low word; C set with Y = errno.</returns>
.proc ksys_seek
    lda #RP_FS_OP_SEEK
    jmp ksys_fs_exec_file_handle
.endproc

; <summary>
; ksys_tell implements tell(fd) for RP filesystem files and writes the
; current unsigned 32-bit position into tell_args.
; </summary>
; <param name="X/Y">Pointer to a tell_args block in the caller context.</param>
; <returns>C clear with A/X = result low word; C set with Y = errno.</returns>
.proc ksys_tell
    lda #RP_FS_OP_TELL
    jmp ksys_fs_exec_file_handle
.endproc



; <summary>
; ksys_delete implements delete(path, device) for RP filesystem files.
; </summary>
; <param name="X/Y">Pointer to a delete_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_delete
    lda #RP_FS_OP_DELETE
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_rename implements rename(old_path, new_path, device) for RP filesystem files.
; </summary>
; <param name="X/Y">Pointer to a rename_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_rename
    lda #RP_FS_OP_RENAME
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_opendir implements opendir(path, device) for RP filesystem
; directories and attaches the resulting RP directory handle to the
; current process FD table as an OBJ_DIR.
; </summary>
; <param name="X/Y">Pointer to an opendir_args block in the caller context.</param>
; <returns>C clear with A = fd and X = 0; C set with Y = errno.</returns>
.proc ksys_opendir
    jsr ksys_fs_begin
    bcs @gate_owned
    sec
    rts
@gate_owned:
    ldy #opendir_args::path_ptr
    jsr ksys_fs_uppercase_path_at_y
    bcc @path_ready
    jmp @fail

@path_ready:
    ldy #opendir_args::flags
    lda (io_ptr),y
    beq @flags_ok
    ldy #EINVAL
    jmp @fail
@flags_ok:
    jsr fd_alloc_open
    bcc @open_obj_ok
    jmp @fail
@open_obj_ok:
    stx ksys_open_obj
    jsr fd_alloc_fd_current
    bcc @fd_ok
    ldx ksys_open_obj
    jsr fd_free_open
    jmp @fail
@fd_ok:
    sty ksys_open_fd
    lda #RP_FS_OP_OPENDIR
    ldx #$FF
    ldy #0
    jsr rp_fs_exec
    bcc @rp_ok
    phy
    ldx ksys_open_obj
    jsr fd_free_open
    ply
    jmp @fail
@rp_ok:
    sty ksys_open_device
    ldx ksys_open_obj
    sta open_file_handle,x
    lda #OBJ_DIR
    sta open_type,x
    lda #FD_FLAG_READ
    sta open_flags,x
    lda ksys_open_device
    sta open_dev,x
    ldy ksys_open_fd
    lda #FD_FLAG_READ
    jsr fd_attach_current
    lda ksys_open_fd
    ldx #0
    clc
    jmp ksys_fs_finish
@fail:
    sec
    jmp ksys_fs_finish
.endproc

; <summary>
; ksys_readdir reads the next entry from a directory fd into a caller
; supplied dir_entry buffer.
; </summary>
; <param name="X/Y">Pointer to a readdir_args block in the caller context.</param>
; <returns>C clear with A/X = 1 when an entry was returned or 0 at EOF; C set with Y = errno.</returns>
.proc ksys_readdir
    jsr ksys_fs_begin
    bcs @owned
    sec
    rts

@owned:
    ldy #readdir_args::fd
    lda (io_ptr),y
    tay
    jsr fd_resolve_dir
    bcs @finish

    ; A is the trusted RP directory handle. The RP validates entry_ptr and
    ; entry_size, then copies the directory entry into the caller context.
    tax
    lda #RP_FS_OP_READDIR
    ldy #0
    jsr rp_fs_exec

@finish:
    jmp ksys_fs_finish
.endproc

; <summary>
; ksys_closedir validates that the supplied fd is a directory fd and then
; closes it through the normal FD close path.
; </summary>
; <param name="X/Y">Pointer to a closedir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_closedir
    jsr ksys_fs_begin
    bcs @owned
    sec
    rts

@owned:
    ldy #closedir_args::fd
    lda (io_ptr),y
    tay
    jsr fd_resolve_dir
    bcs @finish

    ; fd_close performs final-reference handling and uses the already-generic
    ; RP closedir request when the directory object is released.
    ldy #closedir_args::fd
    lda (io_ptr),y
    jsr fd_close

@finish:
    jmp ksys_fs_finish
.endproc
; <summary>
; ksys_chdir changes the current process cwd after validating the resolved
; directory with RP OPENDIR/CLOSEDIR. No RP global cwd is modified.
; </summary>
; <param name="X/Y">Pointer to a chdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_chdir
    lda #RP_FS_OP_CHDIR
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_mkdir creates a directory after resolving the caller path against the
; current process cwd. RP receives only an explicit resolved path and device.
; </summary>
; <param name="X/Y">Pointer to a mkdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_mkdir
    lda #RP_FS_OP_MKDIR
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_rmdir removes an empty directory after resolving the caller path against
; the current process cwd. RP receives only an explicit resolved path and device.
; </summary>
; <param name="X/Y">Pointer to a rmdir_args block in the caller context.</param>
; <returns>C clear with A/X = 0; C set with Y = errno.</returns>
.proc ksys_rmdir
    lda #RP_FS_OP_RMDIR
    jmp ksys_fs_exec_no_handle
.endproc

; <summary>
; ksys_getcwd copies the current process cwd as D:/PATH into a caller buffer.
; </summary>
; <param name="X/Y">Pointer to a getcwd_args block in the caller context.</param>
; <returns>C clear with A = result length and X = 0; C set with Y = errno.</returns>
.proc ksys_getcwd
    lda #RP_FS_OP_GETCWD
    jmp ksys_fs_exec_no_handle
.endproc

