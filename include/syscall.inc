; ============================================================
; syscall.inc
; NEOX - syscall definitions
;
; Purpose:
;   Defines syscall numbers, fixed syscall entry addresses,
;   error codes, and common syscall argument structures.
;
; Architecture:
;   - Syscall jump table is located in shared page C
;   - Each syscall entry is a 3-byte JMP stub
;   - User code calls fixed syscall entry addresses
;
; Notes:
;   SYS_MONITOR enters supervisor/MICMON context through the
;   kernel-defined monitor entry path. It is a controlled
;   privileged transfer, not direct user control of MMU/scheduler.
; ============================================================

.ifndef __SYSCALL_INC__
__SYSCALL_INC__ = 1

.include "config.inc"

SYSCALL_ENTRY_SIZE  = 3

; ------------------------------------------------------------
; Standard file descriptors
; ------------------------------------------------------------

STDIN               = 0
STDOUT              = 1
STDERR              = 2

; ------------------------------------------------------------
; Syscall numbers
; ------------------------------------------------------------
SYS_EXIT			= $00
SYS_OPEN            = $01
SYS_CLOSE			= $02
SYS_READ            = $03
SYS_WRITE           = $04
SYS_MONITOR         = $05
SYS_LOAD_FILE_TO_MEMORY = $06
SYS_SAVE_MEMORY_TO_FILE = $07
SYS_SEEK            = $08
SYS_TELL            = $09
SYS_PIPE			= $0A
SYS_DELETE          = $0C
SYS_RENAME          = $0D
SYS_YIELD           = $0B
SYS_SLEEP           = $0E
SYS_DUP				= $0F
SYS_DUP2			= $10
SYS_TICKS           = $11
SYS_SIGNAL          = $12
SYS_OPENDIR         = $13
SYS_READDIR         = $14
SYS_CLOSEDIR        = $15
SYS_CHDIR           = $16
SYS_GETCWD          = $17
SYS_MKDIR           = $18
SYS_RMDIR           = $19
SYS_GETPROCINFO     = $1A
SYS_SPAWN_ALLOC_RESIDENT = $1B
SYS_SPAWN_FD_INHERIT = $1C
SYS_SPAWN_FD_DUP_CHILD = $1D
SYS_SPAWN_FD_CLOSE   = $1E
SYS_SPAWN_COMMIT     = $1F
SYS_SPAWN_ABORT      = $20
SYS_WAITPID          = $21
SYS_SPAWN_SET_LAUNCH_ID = $22
SYS_GET_LAUNCH_ID   = $23
SYS_SPAWN_SET_ARGS2 = $24
SYS_GET_LAUNCH_ARGS2 = $25

; ------------------------------------------------------------
; Fixed syscall entry addresses
; ------------------------------------------------------------

sys_exit            = SYSCALL_BASE + (SYS_EXIT    * SYSCALL_ENTRY_SIZE)
sys_open            = SYSCALL_BASE + (SYS_OPEN    * SYSCALL_ENTRY_SIZE)
sys_close           = SYSCALL_BASE + (SYS_CLOSE   * SYSCALL_ENTRY_SIZE)
sys_read            = SYSCALL_BASE + (SYS_READ    * SYSCALL_ENTRY_SIZE)
sys_write           = SYSCALL_BASE + (SYS_WRITE   * SYSCALL_ENTRY_SIZE)
sys_monitor         = SYSCALL_BASE + (SYS_MONITOR * SYSCALL_ENTRY_SIZE)
sys_load_file_to_memory = SYSCALL_BASE + (SYS_LOAD_FILE_TO_MEMORY * SYSCALL_ENTRY_SIZE)
sys_save_memory_to_file = SYSCALL_BASE + (SYS_SAVE_MEMORY_TO_FILE * SYSCALL_ENTRY_SIZE)
sys_seek            = SYSCALL_BASE + (SYS_SEEK    * SYSCALL_ENTRY_SIZE)
sys_tell            = SYSCALL_BASE + (SYS_TELL    * SYSCALL_ENTRY_SIZE)
sys_delete          = SYSCALL_BASE + (SYS_DELETE  * SYSCALL_ENTRY_SIZE)
sys_rename          = SYSCALL_BASE + (SYS_RENAME  * SYSCALL_ENTRY_SIZE)
sys_pipe            = SYSCALL_BASE + (SYS_PIPE    * SYSCALL_ENTRY_SIZE)
sys_yield           = SYSCALL_BASE + (SYS_YIELD   * SYSCALL_ENTRY_SIZE)
sys_sleep           = SYSCALL_BASE + (SYS_SLEEP   * SYSCALL_ENTRY_SIZE)
sys_dup				= SYSCALL_BASE + (SYS_DUP     * SYSCALL_ENTRY_SIZE)
sys_dup2			= SYSCALL_BASE + (SYS_DUP2    * SYSCALL_ENTRY_SIZE)
sys_ticks           = SYSCALL_BASE + (SYS_TICKS   * SYSCALL_ENTRY_SIZE)
sys_signal          = SYSCALL_BASE + (SYS_SIGNAL  * SYSCALL_ENTRY_SIZE)
sys_opendir         = SYSCALL_BASE + (SYS_OPENDIR * SYSCALL_ENTRY_SIZE)
sys_readdir         = SYSCALL_BASE + (SYS_READDIR * SYSCALL_ENTRY_SIZE)
sys_closedir        = SYSCALL_BASE + (SYS_CLOSEDIR * SYSCALL_ENTRY_SIZE)
sys_chdir           = SYSCALL_BASE + (SYS_CHDIR * SYSCALL_ENTRY_SIZE)
sys_getcwd          = SYSCALL_BASE + (SYS_GETCWD * SYSCALL_ENTRY_SIZE)
sys_mkdir           = SYSCALL_BASE + (SYS_MKDIR * SYSCALL_ENTRY_SIZE)
sys_rmdir           = SYSCALL_BASE + (SYS_RMDIR * SYSCALL_ENTRY_SIZE)
sys_getprocinfo     = SYSCALL_BASE + (SYS_GETPROCINFO * SYSCALL_ENTRY_SIZE)
sys_spawn_alloc_resident = SYSCALL_BASE + (SYS_SPAWN_ALLOC_RESIDENT * SYSCALL_ENTRY_SIZE)
sys_spawn_fd_inherit = SYSCALL_BASE + (SYS_SPAWN_FD_INHERIT * SYSCALL_ENTRY_SIZE)
sys_spawn_fd_dup_child = SYSCALL_BASE + (SYS_SPAWN_FD_DUP_CHILD * SYSCALL_ENTRY_SIZE)
sys_spawn_fd_close = SYSCALL_BASE + (SYS_SPAWN_FD_CLOSE * SYSCALL_ENTRY_SIZE)
sys_spawn_commit = SYSCALL_BASE + (SYS_SPAWN_COMMIT * SYSCALL_ENTRY_SIZE)
sys_spawn_abort = SYSCALL_BASE + (SYS_SPAWN_ABORT * SYSCALL_ENTRY_SIZE)
sys_waitpid = SYSCALL_BASE + (SYS_WAITPID * SYSCALL_ENTRY_SIZE)
sys_spawn_set_launch_id = SYSCALL_BASE + (SYS_SPAWN_SET_LAUNCH_ID * SYSCALL_ENTRY_SIZE)
sys_get_launch_id = SYSCALL_BASE + (SYS_GET_LAUNCH_ID * SYSCALL_ENTRY_SIZE)
sys_spawn_set_args2 = SYSCALL_BASE + (SYS_SPAWN_SET_ARGS2 * SYSCALL_ENTRY_SIZE)
sys_get_launch_args2 = SYSCALL_BASE + (SYS_GET_LAUNCH_ARGS2 * SYSCALL_ENTRY_SIZE)

; ------------------------------------------------------------
; Common errno values
; ------------------------------------------------------------

E_OK                = 0
EIO                 = 3
EINVAL              = 6
EMFILE              = 8        ; too many open file descriptors
EBADF               = 9
ENODEV              = 10
ENOSYS              = 11
EAGAIN              = 12       ; operation would block / try again
ENOMEM              = 13       ; no free kernel memory/object/table slot
EPIPE               = 14       ; write on pipe with no readers

.include "spawn.inc"

; ------------------------------------------------------------
; Common open argument block
;
; path_ptr:
;   Pointer to a NUL-terminated 8.3 filename in the current task
;   context. The RP-side FS_OPEN command scans at most max_len bytes.
;
; max_len:
;   Maximum filename scan length. Use a small bounded value such as 64.
;
; flags:
;   Open mode. V32 supports read-only, write/truncate, write-existing,
;   read/write-existing, and read/write-create.
;
; device:
;   RP filesystem device/FatFs drive number: 0..3.
; ------------------------------------------------------------

.struct open_args
    path_ptr        .word
    max_len         .word
    flags           .byte
    device          .byte
.endstruct

OPEN_ARGS_SIZE = .sizeof(open_args)

OPEN_READ           = $00    ; read existing
OPEN_WRITE_TRUNC    = $01    ; write create/truncate
OPEN_WRITE_EXISTING = $02    ; write existing, no truncate
OPEN_RW_EXISTING    = $03    ; read/write existing, no truncate
OPEN_RW_CREATE      = $04    ; read/write create if missing, no truncate if existing


; ------------------------------------------------------------
; Bulk filesystem argument blocks
;
; Names and paths use NEOX 8.3 path components. The path string is
; NUL-terminated and is validated by the RP side.
;
; max_bytes / byte_count:
;   $0000 means 65536 bytes.
;
; flags:
;   Reserved for now. Must be 0.
;
; Context rule:
;   User code never supplies a context. The kernel derives the caller
;   context and passes it separately to the RP mailbox in ARG2L.
; ------------------------------------------------------------

.struct fs_load_args
    path_ptr        .word
    dest_ptr        .word
    max_bytes       .word
    device          .byte
    flags           .byte
.endstruct

FS_LOAD_ARGS_SIZE = .sizeof(fs_load_args)

.struct fs_save_args
    path_ptr        .word
    src_ptr         .word
    byte_count      .word
    device          .byte
    flags           .byte
.endstruct

FS_SAVE_ARGS_SIZE = .sizeof(fs_save_args)

FS_BULK_FLAGS_NONE = $00


; ------------------------------------------------------------
; Seek/tell filesystem argument blocks
;
; offset_lo/offset_hi:
;   Signed 32-bit offset split into low/high words.  SEEK_SET
;   requires a non-negative final target; SEEK_CUR and SEEK_END
;   allow negative offsets.
;
; result_lo/result_hi:
;   Kernel writes the resulting unsigned 32-bit file position here.
;   A/X also return result_lo for convenience.
; ------------------------------------------------------------

SEEK_SET            = $00
SEEK_CUR            = $01
SEEK_END            = $02

.struct seek_args
    fd              .byte
    whence          .byte
    offset_lo       .word
    offset_hi       .word
    result_lo       .word
    result_hi       .word
.endstruct

SEEK_ARGS_SIZE = .sizeof(seek_args)

.struct tell_args
    fd              .byte
    reserved        .byte
    result_lo       .word
    result_hi       .word
.endstruct

TELL_ARGS_SIZE = .sizeof(tell_args)


; ------------------------------------------------------------
; Delete/rename filesystem argument blocks
;
; V34 path handling uses the same RP-side 8.3 validator as open.
; flags is reserved and must be 0.
; ------------------------------------------------------------

FS_PATH_FLAGS_NONE  = $00

.struct delete_args
    path_ptr        .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

DELETE_ARGS_SIZE = .sizeof(delete_args)

.struct rename_args
    old_path_ptr    .word
    new_path_ptr    .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

RENAME_ARGS_SIZE = .sizeof(rename_args)

; ------------------------------------------------------------
; Common read/write argument block
;
; fd:
;   STDIN / STDOUT / STDERR
;
; buf_ptr:
;   Pointer to caller buffer in the current task context
;
; len:
;   Requested transfer length
; ------------------------------------------------------------

.struct rw_args
    fd              .byte
    reserved        .byte
    buf_ptr         .word
    len             .word
.endstruct

RW_ARGS_SIZE = .sizeof(rw_args)

; ------------------------------------------------------------
; SYSCALL helper macro
;
; Purpose:
;   Load X/Y with the address of an argument block and call the
;   fixed syscall entry.
;
; Example:
;   SYSCALL my_args, sys_write
; ------------------------------------------------------------

.macro SYSCALL argblk, entry
    ; Keep the register argument pointer stable across the tiny user-side
    ; setup window. The kernel snapshots the process-private pointer before
    ; taking file_io_gate and decodes the block after the owner resumes.
    sei
    ldx #<argblk
    ldy #>argblk
    jsr entry
.endmacro


; ------------------------------------------------------------
; Directory control argument blocks
;
; V35 exposes directory handles as normal NEOX fd numbers. The RP
; directory handle remains kernel-private in the FD/open-object table.
;
; dir_entry layout matches the RP serialized directory entry:
;   name[13] = NUL-terminated 8.3 name
;   attr     = FatFs attribute byte
;   size     = unsigned 32-bit byte size
; ------------------------------------------------------------

DIR_ENTRY_NAME_SIZE = 13
DIR_ENTRY_SIZE      = 18

.struct dir_entry
    name            .res 13
    attr            .byte
    size_lo         .word
    size_hi         .word
.endstruct

.struct opendir_args
    path_ptr        .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

OPENDIR_ARGS_SIZE = .sizeof(opendir_args)

.struct readdir_args
    fd              .byte
    reserved        .byte
    entry_ptr       .word
    entry_size      .word
.endstruct

READDIR_ARGS_SIZE = .sizeof(readdir_args)

.struct closedir_args
    fd              .byte
    reserved        .byte
.endstruct

CLOSEDIR_ARGS_SIZE = .sizeof(closedir_args)

; ------------------------------------------------------------
; Current directory argument blocks
;
; V36 stores current directory per process as drive + absolute path.
; User-visible getcwd form is D:/PATH.
; ------------------------------------------------------------

NEOX_PATH_FLAGS_NONE = $00

.struct chdir_args
    path_ptr        .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

CHDIR_ARGS_SIZE = .sizeof(chdir_args)

.struct getcwd_args
    buffer_ptr      .word
    buffer_size     .word
    result_len      .word
    flags           .byte
    reserved        .byte
.endstruct

GETCWD_ARGS_SIZE = .sizeof(getcwd_args)

; ------------------------------------------------------------
; Directory create/remove argument blocks
; ------------------------------------------------------------

.struct mkdir_args
    path_ptr        .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

MKDIR_ARGS_SIZE = .sizeof(mkdir_args)

.struct rmdir_args
    path_ptr        .word
    max_len         .word
    device          .byte
    flags           .byte
.endstruct

RMDIR_ARGS_SIZE = .sizeof(rmdir_args)

; ------------------------------------------------------------
; Process information argument block
;
; SYS_GETPROCINFO copies one compact process-table snapshot record
; into caller memory.  The record is deliberately binary; user-space
; commands such as PS own all text formatting.
;
; Record layout:
;   +0 pid
;   +1 ppid
;   +2 state
;   +3 wait_reason
;   +4 signal_pending
;   +5 wait_object
;   +6 held_gate_mask (PROC_HOLD_*)
;
; Kernels accepting the extended record remain compatible with callers
; that provide the original five-byte buffer.
; ------------------------------------------------------------

PROCINFO_RECORD_MIN_SIZE = 5
PROCINFO_RECORD_SIZE     = 7

.struct procinfo_args
    pid             .byte
    reserved        .byte
    buffer_ptr      .word
    buffer_size     .word
.endstruct

PROCINFO_ARGS_SIZE = .sizeof(procinfo_args)

.endif
