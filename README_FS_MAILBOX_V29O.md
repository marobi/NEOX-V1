# V29O - 6502 filesystem syscall layer over mailbox ABI v2

This version adds the first NEOX-side read-only filesystem path on top of the
already-migrated RP mailbox ABI v2.

## Scope

Added:

- `kernel/rp_fs_io.asm`
  - filesystem mailbox usage only
  - `FS_STATUS`, `FS_OPEN`, `FS_READ`, `FS_CLOSE`
  - uses `RP_GROUP_FS` and `RP_FS_CMD_*`

- `kernel/ksys_fs.asm`
  - kernel `open()` syscall implementation
  - read-only file open through RP FS
  - attaches RP file handles into the FD/open-object table

Updated:

- `include/syscall.inc`
  - defines `SYS_OPEN = $01`
  - defines `sys_open`
  - adds `open_args`

- `include/kernel.inc` and `kernel/entry_table.asm`
  - adds `KERN_ENTRY_KSYS_OPEN`

- `kernel/syscall_table.asm`
  - `k_open` now jumps to the kernel open implementation

- `kernel/fd.asm` / `kernel/shared_state.asm`
  - `OBJ_FILE` now represents RP filesystem files
  - open objects store `open_file_handle[object]`
  - `fd_read` dispatches `OBJ_FILE` to `rp_fs_read`
  - last close of an `OBJ_FILE` calls `rp_fs_close`

- `Makefile`
  - builds `kernel/ksys_fs.asm`
  - builds `kernel/rp_fs_io.asm`

## Open ABI

User-side `sys_open` expects X/Y to point to:

```asm
.struct open_args
    path_ptr        .word   ; NUL-terminated 8.3 filename
    max_len         .word   ; bounded filename scan length, e.g. 64
    flags           .byte   ; only 0 currently accepted
    device          .byte   ; RP filesystem device / FatFs drive 0..3
.endstruct
```

Return:

- C clear: A = fd, X = 0
- C set: Y = errno

## Current limitations

- read-only files only
- no seek/write/sync/stat/opendir/readdir yet
- paths are still 8.3 root-style filenames for the current RP FS layer
- `write()` to file FDs is unsupported

## Build note

Use a full clean rebuild after this change because `syscall.inc`, the kernel
entry table, and shared-state layout changed.
