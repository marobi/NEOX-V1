# NEOX

NEOX is a minimal UNIX-like operating system for the **NEO6502-MMU platform**.

The system is designed to be:

* deterministic
* inspectable
* explicitly layered
* free of hidden runtime behavior

---

## Platform: NEO6502-MMU

NEOX runs on a heterogeneous system:

* **W65C02 CPU** (kernel + user execution)
* **RP2350** (I/O, MMU switching, external services)

### RP2350 responsibilities

* MMU context switching
* console and device I/O
* mailbox protocol handling

The 6502 owns all OS logic.

---

## Architecture Overview

### Execution model

* Kernel and user processes run on the 6502
* RP2350 provides asynchronous services via mailbox
* Timer IRQ drives preemptive scheduling

---

## Memory Model

### Context-based execution

* **Context 0**

  * supervisor / monitor (MICMON)
  * not scheduled

* **Contexts 1..N**

  * user/kernel processes
  * scheduled by kernel

---

### Logical memory layout

| Page | Type    | Description     |
| ---- | ------- | --------------- |
| 0–7  | Private | ZP, stack, heap |
| 8–A  | Shared  | shared RAM      |
| B    | Shared  | MICMON          |
| C    | Shared  | syscall veneer  |
| D    | Shared  | RP I/O          |
| E    | Shared  | kernel          |
| F    | Shared  | BIOS            |

Key properties:

* ZP and stack are private per context
* shared state must live in shared pages

---

## Scheduler

### Properties

* timer-driven (IRQ)
* round-robin
* preemptive
* context-based

### Process states

```
EMPTY → NEW → RUNNING ↔ READY
             ↘ BLOCKED
```

### Blocking

Processes may enter `PROC_BLOCKED` when waiting for I/O.

---

## Console Model

### Key variables

```
console_owner_pid   = process allowed to read input
console_wait_pid    = process blocked waiting for input
RP_CONSOLE_PID      = RP/user-selected focus (external)
RP_CONSOLE_RDY      = input available flag
```

---

### Ownership

* `RP_CONSOLE_PID` is set by the RP/user interface
* kernel validates and mirrors into:

```
console_owner_pid
```

* only `console_owner_pid` may consume console input

---

### Blocking behavior

For a process calling `read`:

```
not owner
    → return 0

owner + no input
    → console_wait_pid = pid
    → process becomes BLOCKED

owner + input ready
    → rp_console_read executes
```

---

### Wake-up

Scheduler performs wake-up:

```
if RP_CONSOLE_RDY != 0 and console_wait_pid != $FF:
    wake console_wait_pid
    console_wait_pid = $FF
```

---

### Invariant

```
if console_wait_pid != $FF:
    console_wait_pid == console_owner_pid
```

---

## Monitor (MICMON)

### Model

* runs in **context 0**
* **not a process**
* **not scheduled**

### Entry

```
save SP of current task
sched_lock_enter
jump to monitor
```

### Exit

```
sched_lock_leave
restore SP
return to interrupted context
```

### Important

Monitor does NOT modify:

```
console_owner_pid
console_wait_pid
RP_CONSOLE_PID
current_pid
proc_state
```

---

## Scheduler Lock

```
sched_lock
```

* disables scheduler preemption
* used during:

  * monitor execution
  * critical kernel operations

---

## Mailbox I/O

### Flow

```
kernel:
    fill request block
    set RP_STATUS = BUSY
    write RP_DOORBELL

RP2350:
    executes request
    sets DONE / ERROR
```

---

### Registers

```
RP_DOORBELL = $D010
RP_STATUS   = $D011
```

---

### Synchronization

* `rp_lock` → mailbox ownership
* `sched_lock` → prevents preemption

---

## FD / Device Layer

### Path

```
ksys_read
 → fd_lookup
 → dev_resolve_op
 → console_read
```

### Device dispatch

```
open_dev → dev_ops → operation table
```

Devices implement:

```
read
write
ioctl
close
```

---

## Syscall Interface

### Layout

```
$C000 = syscall veneer
```

* fixed ABI
* each syscall = `JMP kernel_entry`

### Current syscalls

| ID | Name  | Description    |
| -- | ----- | -------------- |
| 3  | read  | console input  |
| 4  | write | console output |

### Calling convention

```
X/Y = pointer to args
C clear = success
C set   = error (Y = errno)
A/X     = return value
```

---

## Project Structure

```
kernel/   → kernel implementation
include/  → shared definitions
build/    → linker configs
user/     → user/test code
```

---

## Current Status

Working:

* scheduler (preemptive, stable)
* context switching
* mailbox I/O
* FD/device layer
* console ownership + blocking + wake
* monitor integration (no corruption of state)

---

## Next Steps

* generalize blocking (beyond console)
* add wait reason abstraction
* extend device layer
* process control syscalls
* filesystem layer

---

## License

TBD
