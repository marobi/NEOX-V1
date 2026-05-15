# NEOX

NEOX is a minimal UNIX-like operating system for the **NEO6502-MMU platform**.

The system is designed to be:

* deterministic
* inspectable
* explicitly layered
* free of hidden runtime behavior

The current implementation is intentionally small. The kernel favors explicit tables, fixed ABI boundaries, and debuggable state over dynamic runtime mechanisms.

---

## Platform: NEO6502-MMU

NEOX runs on a heterogeneous system:

* **W65C02 CPU** — kernel and user execution
* **RP2350** — I/O, MMU switching, console services, external services

### RP2350 responsibilities

* MMU context switching support
* console and device I/O
* mailbox protocol handling
* external service execution requested by the 6502

The **6502 owns all OS policy and process state**. The RP2350 acts as an I/O and platform service processor.

---

## Architecture Overview

### Execution model

* Kernel and user processes run on the W65C02.
* RP2350 services are requested through a mailbox protocol.
* Timer IRQ drives preemptive scheduling.
* Processes execute in MMU contexts.
* Context 0 is reserved for idle/supervisor/monitor use.

### Design rules

* Syscalls enter through a fixed veneer.
* Kernel entry points are explicit.
* Process metadata is stored in kernel-owned tables.
* Shared kernel state lives in shared memory pages.
* PID 0 is special and is not treated as a normal user process.

---

## Memory Model

### Context-based execution

* **Context 0**

  * idle / supervisor context
  * monitor context for MICMON
  * not part of normal process scheduling

* **Contexts 1..N**

  * process contexts
  * scheduled by the kernel

---

### Logical memory layout

| Page | Type    | Description     |
| ---- | ------- | --------------- |
| 0–7  | Private | ZP, stack, heap / process-private memory |
| 8–A  | Shared  | shared RAM      |
| B    | Shared  | MICMON          |
| C    | Shared  | syscall veneer  |
| D    | Shared  | RP I/O          |
| E    | Shared  | kernel          |
| F    | Shared  | BIOS            |

Key properties:

* Zero page and stack are private per context.
* Kernel-visible shared state must live in shared pages.
* Context switching is explicit and performed through BIOS/MMU entry points.

---

## Process Model

### Process identity

Each process has:

* PID
* PPID
* state
* pending signal
* saved stack pointer
* MMU context
* flags
* wait reason / wait object
* per-process file descriptor table

PID 0 is reserved:

* parent PID is `$FF`
* context is 0
* used as idle/supervisor fallback
* not a normal schedulable process

---

### Process states

Current process states:

```text
EMP  = empty slot
NEW  = created but not yet started
RDY  = ready to run
RUN  = currently running
BLK  = blocked on wait object
STP  = stopped by process-control signal
```

Normal lifecycle:

```text
EMP -> NEW -> RUN -> RDY -> RUN
                \-> BLK -> RDY
                \-> STP -> RDY
                \-> EMP
```

### Important invariant

PID 0 is idle/supervisor-special:

```text
PID 0 is not inserted into the normal READY queue.
PID 0 is not saved/restored through proc_sp[0].
PID 0 is entered directly through idle_loop in context 0.
```
---

## Scheduler

### Properties

* timer-driven IRQ scheduling
* round-robin process selection
* preemptive scheduling for normal processes
* explicit blocking and wake-up
* context-based resume

### Resume modes

The scheduler tracks how a process stack must be resumed:

```text
PROC_RESUME_RTI = process was interrupted by IRQ
PROC_RESUME_RTS = process yielded through syscall/kernel path
```

IRQ-preempted processes resume through an RTI-compatible frame.
Voluntary-yielded processes resume through an RTS-compatible frame.

### Scheduler entry paths

```text
timer IRQ       -> sched_context_switch
voluntary yield -> sched_yield
monitor exit    -> sched_yield
```

PID 0 is handled specially in both scheduler paths. If the scheduler selects PID 0, it jumps directly to `idle_loop` instead of restoring `proc_sp[0]`.

---

## Blocking and Wake-up

Processes block by setting:

```text
wait_reason
wait_object
proc_state = BLK
```

Current wait reasons include:

```text
TIM = timer wait
CON = console input wait
```

Timer wake-up is driven from the scheduler/timer path. Console wake-up is driven by the console-ready state exposed by the RP2350.

---

## Console Model

### Key variables

```text
console_owner_pid = process allowed to read input
RP_CONSOLE_RDY    = input available flag
```

The active console owner is the process allowed to consume console input. Other processes may hold console file descriptors, but they cannot read input unless they own the console.

---

### Ownership

* console ownership is tracked by the kernel
* only `console_owner_pid` may consume input
* console focus can change externally through the RP/user interface
* the scheduler updates console focus state during wake/check paths

---

### Read behavior

For a process calling `read` on the console device:

```text
not owner
    -> return 0 bytes

owner + no input
    -> process becomes BLK on CON
    -> scheduler runs another process

owner + input ready
    -> RP console read executes
    -> bytes returned to caller
```

Console reads are implemented in the console device backend. The FD/syscall layer does not contain console-specific blocking logic.

---

## Monitor (MICMON)

### Model

* runs in **context 0**
* not a normal process
* not selected by the scheduler as a user process
* protected by `sched_lock`

### Entry

Monitor entry from IRQ records the interrupted owner and enters context 0.

If a normal process was interrupted:

```text
save its SP
mark resume mode as RTI
convert RUN -> RDY
enter monitor
```

If PID 0 was interrupted:

```text
do not save proc_sp[0]
do not convert PID 0 RUN -> RDY
enter monitor directly
```

### Exit

Monitor exit:

```text
sched_lock_leave
sched_yield
```

Normal scheduling then resumes. If no normal process is runnable, the scheduler enters `idle_loop` directly in context 0.

---

## Scheduler Lock

```text
sched_lock
```

`sched_lock` prevents scheduler preemption while critical supervisor/monitor code is active.

Used during:

* monitor execution
* critical kernel transitions

Timer IRQ does not run a context switch while the scheduler lock is held.

---

## Mailbox I/O

### Flow

```text
kernel:
    acquire rp_lock
    wait for RP_STATUS == IDLE
    fill request block
    set RP_STATUS = BUSY
    write RP_DOORBELL

RP2350:
    executes request
    sets DONE / ERROR

kernel:
    reads result
    sets RP_STATUS = IDLE
    releases rp_lock
```

---

### Registers

```text
RP_DOORBELL = $D010
RP_STATUS   = $D011
```

### Synchronization

* `rp_lock` serializes mailbox ownership.
* `sched_lock` prevents scheduler transitions during protected sections.
* IRQ handlers must not use the RP mailbox path.

---

## FD / Device Layer

The FD/device layer is now separated from syscall argument decoding.

### Read/write path

```text
ksys_read / ksys_write
    -> decode syscall argument block
    -> fd_read / fd_write
        -> fd lookup for current process
        -> permission check
        -> open-object lookup
        -> object type check
        -> device operation dispatch
            -> console_read / console_write
```

### Close path

```text
ksys_close
    -> fd_close
        -> fd lookup for current process
        -> clear process fd entry
        -> clear process fd flags
        -> decrement open-object refcount
        -> call device close when final reference is closed
```

### Tables

The current model uses:

```text
proc_fd_obj[pid][fd]     = open object index
proc_fd_flags[pid][fd]   = per-process fd permissions
open_type[obj]           = object type
open_refcnt[obj]         = reference count
open_dev[obj]            = backing device id
```

### Permissions

Read/write validation is enforced in the FD layer:

```text
read(fd)  requires FD_FLAG_READ
write(fd) requires FD_FLAG_WRITE
```

Invalid fd or wrong access direction returns:

```text
C set
Y = EBADF
```

Current standard descriptors:

```text
fd 0 = stdin   read-only
fd 1 = stdout  write-only
fd 2 = stderr  write-only
```

### Device dispatch

Device objects resolve through an operation table:

```text
open_dev -> dev_ops -> operation pointer
```

Devices implement:

```text
read
write
ioctl
close
```

The current implemented device is:

```text
CON = console device
```

---

## Syscall Interface

### Layout

```text
$C000 = syscall veneer
```

* fixed ABI
* each syscall veneer jumps to a kernel entry
* kernel wrappers decode syscall argument blocks
* FD/device logic lives below the syscall layer

### Current syscalls

| ID | Name  | Description                         |
| -- | ----- | ----------------------------------- |
| 3  | read  | read from file descriptor           |
| 4  | write | write to file descriptor            |
| —  | close | close a file descriptor             |
| —  | exit  | terminate current process           |
| —  | yield | voluntarily yield the CPU           |

The final syscall ID table is still evolving. The syscall ABI is fixed in structure, but the exported syscall set is still under active development.

### Calling convention

For argument-block syscalls:

```text
X/Y = pointer to args
C clear = success
C set   = error, Y = errno
A/X     = return value where applicable
```

For simple scalar syscalls such as close:

```text
A = scalar argument, for example fd number
C clear = success
C set   = error, Y = errno
```

---

## Process Termination

Process termination is centralized through `proc_terminate`.

Termination is responsible for:

* refusing to terminate PID 0
* closing process-owned file descriptors
* clearing wait state
* clearing pending signal
* storing exit code
* releasing the process slot

Current model:

```text
No zombie state yet.
Terminated processes immediately become EMP.
Exit code is retained only as kernel/debug state until wait() exists.
```

---

## Process Control

Basic process-control signals exist as pending process events:

```text
SIG_HALT
SIG_CONT
SIG_KILL
```

Current behavior:

* `SIG_HALT` moves a process to `STP`
* `SIG_CONT` moves a stopped process back to `RDY`
* `SIG_KILL` terminates through `proc_terminate`

These are kernel process-control signals, not full UNIX signal handlers.

---

## Debugging

The kernel is designed to be inspectable from the monitor.

The `ps` output currently exposes:

* scheduler lock
* current PID
* current context
* console owner
* RP lock
* process table
* wait reason / wait object
* per-process file descriptors
* global open-object table
* RP status fields
* optional scheduler debug markers

Temporary diagnostic code should be marked clearly:

```asm
; DEBUG BEGIN: description
    ; temporary diagnostic code
; DEBUG END: description
```

This makes debug code easy to remove once a subsystem stabilizes.

---

## Project Structure

```text
kernel/   -> kernel implementation
include/  -> shared definitions
build/    -> linker configs
bios/     -> BIOS interfaces / platform entry points
user/     -> user/test code
```

---

## Current Status

Working:

* timer-driven preemptive scheduler
* context switching
* PID 0 idle/supervisor handling
* monitor entry/exit without corrupting PID 0 state
* timer blocking and wake-up
* console ownership and blocking read
* RP2350 mailbox I/O
* FD read/write dispatch
* FD permission validation
* FD close and refcount decrement
* console device backend
* process termination cleanup path
* basic process-control signal infrastructure

Validated behavior includes:

* console I/O through FD/device dispatch
* `write(0)` fails because stdin is read-only
* `read(1)` fails because stdout is write-only
* `close(1)` clears only the calling process' stdout
* `write(1)` fails after `close(1)`
* `write(2)` still works after stdout is closed

---

## Next Steps

Near-term:

* add `dup` / `dup2` to exercise FD refcounts
* add explicit `open` object allocation/release policy
* add proper device close behavior for non-static objects
* extend process-control syscalls
* decide whether to add zombie/wait semantics

Later:

* filesystem layer
* pipe or stream objects
* richer device model
* user program loading / exec model

---

## License

TBD
