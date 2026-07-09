# Syscall ABI

The syscall ABI exposes fixed entry addresses to user code. Each syscall entry is a 3-byte jump-table stub derived from the syscall number.

## Standard file descriptors

```text
0 STDIN
1 STDOUT
2 STDERR
```

## Calling styles

Two styles are used:

```text
register-style call
  small arguments directly in registers

argument-block call
  X/Y point at a caller-owned argument block
```

The common `SYSCALL argblk, entry` macro loads X/Y with the argument block address and calls the fixed syscall entry.

## Complete syscall summary

| Number | Name | Summary |
|---:|---|---|
| $00 | `SYS_EXIT` | Exit current process. Parent-owned children become waitable zombies. |
| $01 | `SYS_OPEN` | Open a file and return a NEOX fd. Uses an `open_args` block. |
| $02 | `SYS_CLOSE` | Close an fd. |
| $03 | `SYS_READ` | Read from fd into caller buffer. Uses `rw_args`. |
| $04 | `SYS_WRITE` | Write from caller buffer to fd. Uses `rw_args`. |
| $05 | `SYS_MONITOR` | Enter supervisor/MicMon path through controlled kernel mechanism. |
| $06 | `SYS_LOAD_FILE_TO_MEMORY` | Bulk load a file into caller memory. Uses `fs_load_args`. |
| $07 | `SYS_SAVE_MEMORY_TO_FILE` | Bulk save caller memory to a file. Uses `fs_save_args`. |
| $08 | `SYS_SEEK` | Seek an open file. Uses `seek_args`. |
| $09 | `SYS_TELL` | Report current file position. Uses `tell_args`. |
| $0A | `SYS_PIPE` | Create a pipe and return read/write fds. |
| $0B | `SYS_YIELD` | Yield CPU to scheduler. |
| $0C | `SYS_DELETE` | Delete a filesystem path. Uses `delete_args`. |
| $0D | `SYS_RENAME` | Rename a filesystem path. Uses `rename_args`. |
| $0E | `SYS_SLEEP` | Sleep/block for a time interval. |
| $0F | `SYS_DUP` | Duplicate an fd to the next available fd slot. |
| $10 | `SYS_DUP2` | Duplicate one fd into a specified fd number. |
| $11 | `SYS_TICKS` | Return system tick count. |
| $12 | `SYS_SIGNAL` | Process-level software signal operation. |
| $13 | `SYS_OPENDIR` | Open a directory and return a directory fd. Uses `opendir_args`. |
| $14 | `SYS_READDIR` | Read one directory entry. Uses `readdir_args`. |
| $15 | `SYS_CLOSEDIR` | Close a directory fd. Uses `closedir_args`. |
| $16 | `SYS_CHDIR` | Change current process cwd. Uses `chdir_args`. |
| $17 | `SYS_GETCWD` | Copy current process cwd to caller buffer. Uses `getcwd_args`. |
| $18 | `SYS_MKDIR` | Create a directory. Uses `mkdir_args`. |
| $19 | `SYS_RMDIR` | Remove a directory. Uses `rmdir_args`. |
| $1A | `SYS_GETPROCINFO` | Copy compact process info record. Uses `procinfo_args`. |
| $1B | `SYS_SPAWN_ALLOC_RESIDENT` | Allocate parent-owned resident setup child. |
| $1C | `SYS_SPAWN_FD_INHERIT` | Inherit/copy an fd from parent to child. |
| $1D | `SYS_SPAWN_FD_DUP_CHILD` | Duplicate one child fd to another child fd. |
| $1E | `SYS_SPAWN_FD_CLOSE` | Close a child fd before commit. |
| $1F | `SYS_SPAWN_COMMIT` | Make setup child runnable. |
| $20 | `SYS_SPAWN_ABORT` | Abort setup child before commit. |
| $21 | `SYS_WAITPID` | Wait for and reap a child zombie. |
| $22 | `SYS_SPAWN_SET_LAUNCH_ID` | Set resident child launch id. |
| $23 | `SYS_GET_LAUNCH_ID` | Child reads its launch id. |
| $24 | `SYS_SPAWN_SET_ARGS2` | Set child argc/arg0/arg1 launch arguments. |
| $25 | `SYS_GET_LAUNCH_ARGS2` | Child reads launch argc/arg0/arg1. |

## Argument blocks

### `open_args`

```text
path_ptr  word
max_len   word
flags     byte
device    byte
```

Open flags:

```text
OPEN_READ
OPEN_WRITE_TRUNC
OPEN_WRITE_EXISTING
OPEN_RW_EXISTING
OPEN_RW_CREATE
```

### `rw_args`

```text
fd        byte
reserved  byte
buf_ptr   word
len       word
```

### Bulk load/save

```text
fs_load_args:
  path_ptr, dest_ptr, max_bytes, device, flags

fs_save_args:
  path_ptr, src_ptr, byte_count, device, flags
```

### Seek/tell

```text
seek_args:
  fd, whence, offset_lo, offset_hi, result_lo, result_hi

tell_args:
  fd, reserved, result_lo, result_hi
```

### Directory calls

```text
opendir_args:
  path_ptr, max_len, device, flags

readdir_args:
  fd, reserved, entry_ptr, entry_size

closedir_args:
  fd, reserved
```

Directory entry layout:

```text
name[13]
attr
size_lo
size_hi
```

### Current directory calls

```text
chdir_args:
  path_ptr, max_len, device, flags

getcwd_args:
  buffer_ptr, buffer_size, result_len, flags, reserved
```

### Process info

```text
procinfo_args:
  pid, reserved, buffer_ptr, buffer_size
```

Process info record:

```text
+0 pid
+1 ppid
+2 state
+3 wait_reason
+4 signal_pending
```
