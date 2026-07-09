# Mailbox ABI

The mailbox is the shared RP/6502 service interface. It is not a filesystem-only interface.

Current mailbox command groups include:

```text
RP_GROUP_CONSOLE = 01
RP_GROUP_FS      = 02
RP_GROUP_SYSTEM  = 03
```

The current central RP command table contains console and filesystem commands. The grouped ABI leaves room for additional system commands later.

## Request/result block

The fixed request/result block begins at `RP_REQ_BASE`.

```text
+00 RP_GROUP     command group
+01 RP_CMD       command inside group
+02 RP_STATUS    IDLE/BUSY/DONE/ERROR
+03 RP_ERR       mailbox error code
+04 RP_FLAGS     command/result flags
+05 RP_STATE     command-specific state
+06 RP_ARG0L     argument 0 low byte
+07 RP_ARG0H     argument 0 high byte
+08 RP_ARG1L     argument 1 low byte
+09 RP_ARG1H     argument 1 high byte
+0A RP_ARG2L     argument 2 low byte
+0B RP_ARG2H     argument 2 high byte
+0C RP_RES0L     result 0 low byte
+0D RP_RES0H     result 0 high byte
+0E RP_RES1L     result 1 low byte
+0F RP_RES1H     result 1 high byte
```

Additional shared RP state bytes are outside the command block:

```text
RP_IRQ_SOURCE
RP_CONSOLE_PID
RP_CONSOLE_RDY
RP_IRQ_STATE
```

## Doorbell model

The current ABI uses a grouped command identity:

```text
RP_GROUP + RP_CMD = command identity
RP_DOORBELL       = trigger only
```

The doorbell value does not encode the command. The 6502 prepares the request block, marks the request busy, triggers the doorbell, and waits for the RP side to complete the request.

## Status values

```text
RP_IDLE   = 00
RP_BUSY   = 01
RP_DONE   = 02
RP_ERROR  = 03
```

## Error values

The RP side reports errors through `RP_ERR`. Current RP-prefixed error values include:

```text
RP_ERR_OK      success
RP_ERR_EPERM   permission/refused operation
RP_ERR_ENOENT  missing file/object
RP_ERR_EIO     I/O error
RP_ERR_ENOMEM  memory/slot exhaustion
RP_ERR_EBUSY   busy/resource not available
RP_ERR_EINVAL  invalid request
RP_ERR_EPIPE   pipe/broken stream condition
```

## Console group

```text
RP_CON_CMD_WRITE  console write
RP_CON_CMD_READ   console read
```

Console commands are not filesystem commands. They are served through the same central mailbox dispatcher but owned by the RP console I/O module.

## Filesystem group

```text
RP_FS_CMD_STATUS
RP_FS_CMD_OPEN
RP_FS_CMD_READ
RP_FS_CMD_CLOSE
RP_FS_CMD_WRITE
RP_FS_CMD_LOAD
RP_FS_CMD_SAVE
RP_FS_CMD_SEEK
RP_FS_CMD_TELL
RP_FS_CMD_DELETE
RP_FS_CMD_RENAME
RP_FS_CMD_OPENDIR
RP_FS_CMD_READDIR
RP_FS_CMD_CLOSEDIR
RP_FS_CMD_MKDIR
RP_FS_CMD_RMDIR
```

Filesystem commands are only one command family within the mailbox ABI.

## Dispatch ownership

The RP side has one central mailbox dispatcher. Individual modules own command semantics:

```text
mailbox.cpp
  transport, request/result fields, central command table, dispatch, status/error helpers

rp_console_io.cpp
  console read/write command semantics and long-running console transfer state

rp_fs_mailbox.cpp
  filesystem command semantics and RP-side file handle state
```

## Blocking and IRQ rules

Mailbox calls are normal task/syscall-level operations. IRQ handlers must not enter filesystem or mailbox paths. If a caller cannot acquire a serialization gate or must wait for a mailbox result, it must block/yield/retry rather than spin forever while holding shared resources.
