# NEOX ABI v1

## Scope

NEOX ABI v1 defines the callable interface between:

* User programs on the 6502
* The NEOX kernel
* The RP2350 supervisor (indirectly via kernel services)

This ABI specifies:

* Syscall invocation
* Argument passing
* Return conventions
* Error handling
* RP2350 request interface

It does **not** define executable format, filesystem, or process model in full.

---

## 1. Platform Assumptions

* CPU: W65C02 (65C02-compatible)
* Toolchain: ca65 / ld65
* Kernel: 6502 assembly
* Syscalls via jump table (no BRK)

---

## 2. Memory Layout

### Fixed Regions

```
$02C0-$02CB   RP2350 request/result block
$C000-...     NEOX syscall jump table
$D000-$DFFF   I/O page (MMU / RP2350 interface)
$E000-...     NEOX kernel image
$FFFA-$FFFF   CPU vectors
```

### RP2350 Request Block

```
$02C0  RP_CMD
$02C1  RP_ARG0L
$02C2  RP_ARG0H
$02C3  RP_ARG1L
$02C4  RP_ARG1H
$02C5  RP_ARG2L
$02C6  RP_ARG2H
$02C7  RP_RES0L
$02C8  RP_RES0H
$02C9  RP_ERR
$02CA  RP_FLAGS
$02CB  RP_STATE
```

Kernel-owned. User code must not access directly.

---

## 3. Syscall Entry

### Base Address

```
SYSCALL_BASE = $C000
ENTRY_SIZE   = 3
```

Each entry:

```asm
jmp k_handler
```

### Invocation

```asm
ldx #<argblk
ldy #>argblk
jsr sys_write
```

---

## 4. Register Convention

### Entry

* X/Y → pointer to argument block
* A → optional scalar (only if defined)

### Return

* Carry clear → success
* Carry set → error
* A/X → return value (A=low, X=high)
* Y → errno (on error)

### Clobbered

* A, X, Y
* Flags (except carry semantics)

---

## 5. Error Model

```
C = 0 → success
C = 1 → failure
Y     → errno
```

### Errno Values

```
0  E_OK
1  EPERM
2  ENOENT
3  EIO
4  ENOMEM
5  EBUSY
6  EINVAL
7  EPIPE
```

---

## 6. Syscall Table (v1)

| Index | Name  | Address |
| ----: | ----- | ------- |
|    00 | exit  | $C000   |
|    01 | open  | $C003   |
|    02 | close | $C006   |
|    03 | read  | $C009   |
|    04 | write | $C00C   |
|    05 | exec  | $C00F   |
|    06 | wait  | $C012   |
|    07 | chdir | $C015   |
|    08 | stat  | $C018   |
|    09 | pipe  | $C01B   |
|    0A | yield | $C01E   |
|    0B | sbrk  | $C021   |
|    0C | ioctl | $C024   |

---

## 7. Argument Blocks

### rw_args (read/write)

```
+0  fd
+1  reserved
+2  buf_ptr lo
+3  buf_ptr hi
+4  len lo
+5  len hi
```

### open_args

```
+0  path lo
+1  path hi
+2  flags
+3  mode
```

### close_args

```
+0  fd
+1  reserved
```

### exec_args

```
+0  path lo
+1  path hi
+2  argv lo
+3  argv hi
+4  env lo
+5  env hi
```

### wait_args

```
+0  pid
+1  flags
+2  status lo
+3  status hi
```

### path1_args

```
+0  path lo
+1  path hi
```

### stat_args

```
+0  path lo
+1  path hi
+2  stat lo
+3  stat hi
```

### pipe_args

```
+0  fds lo
+1  fds hi
```

### sbrk_args

```
+0  delta lo
+1  delta hi
```

### ioctl_args

```
+0  fd
+1  cmd
+2  arg lo
+3  arg hi
```

---

## 8. Special Cases

### exit

```
A = exit code
X/Y ignored
```

### yield

```
X/Y ignored
```

---

## 9. RP2350 Interface

### Flow

```
user → syscall → kernel → RP2350
```

### Registers

```
$D010  RP_DOORBELL
$D011  RP_STATUS
```

### Status Values

```
0  IDLE
1  BUSY
2  DONE
3  ERROR
```

### Protocol

1. Kernel fills request block
2. Kernel sets RP_STATUS = BUSY
3. Kernel writes RP_DOORBELL
4. RP2350 processes request
5. RP2350 writes result
6. RP2350 sets DONE or ERROR

---

## 10. Rules

### User Code

Must not:

* Access RP request block directly
* Access I/O page for syscalls
* Assume register preservation

### Kernel

Must:

* Keep syscall table stable
* Preserve argument layouts
* Preserve error conventions

### RP2350

Must:

* Treat request block as stable ABI
* Use doorbell as trigger only
* Avoid exposing protocol to userland

---

## 11. Versioning

```
NEOX ABI v1
```

Breaking changes require new ABI version:

* syscall table layout
* argument structures
* return conventions
* RP block layout

---

## 12. Verified Execution Path

```
RESET
 → _user_entry
 → sys_write
 → k_write
 → rp_console_write
 → RP2350
```

This confirms:

* syscall dispatch
* argument passing
* mailbox protocol
* RP integration

---

## Status

NEOX ABI v1 is **implementation-proven** for `sys_write`.

Next expansion target: `sys_read`.
