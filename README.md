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
* loading configured ROM images into MMU contexts during system setup

The **6502 owns all OS policy and process state**. The RP2350 acts as an I/O and platform service processor.

---

## Architecture Overview

### Execution model

* Kernel and user processes run on the W65C02.
* RP2350 services are requested through a mailbox protocol.
* Timer IRQ drives preemptive scheduling.
* Processes execute in MMU contexts.
* Context 0 is reserved for idle/supervisor/monitor use.
* User process code is no longer stored in kernel text.
* Boot-time user processes are created from a user-image entry table.

### Design rules

* Syscalls enter through a fixed veneer.
* Kernel entry points are explicit.
* Process metadata is stored in kernel-owned tables.
* Shared kernel state lives in shared memory pages.
* PID 0 is special and is not treated as a normal user process.
* User/test program code lives in the user image, not in `KERN_TEXT`.

---

## Memory Model

### Context-based execution

* **Context 0**

  * idle / supervisor context
  * monitor context for MICMON
  * kernel boot context
  * reads the user image entry table during boot
  * not part of normal user process scheduling

* **Contexts 1..N**

  * process contexts
  * scheduled by the kernel
  * contain private user image mappings

---

### Current logical memory layout

The kernel has been moved from the old `$E000` 4 KB area to a larger `$8000` region.

| Range         | Type            | Description                          |
| ------------- | --------------- | ------------------------------------ |
| `$0000-$1FFF` | Private/context | ZP, stack, low private RAM           |
| `$2000+`      | Private/context | user image entry table and user code |
| `$8000-$BFFF` | Shared/kernel   | NEOX kernel                          |
| `$C000-$CFFF` | Shared          | syscall veneer                       |
| `$C800-$C8FF` | Shared          | kernel shared state                  |
| `$D000-$DFFF` | Shared          | RP I/O page                          |
| `$E000-$EFFF` | Shared          | MICMON / monitor area                |
| `$F000-$FFFF` | Shared          | BIOS                                 |

Key properties:

* Zero page and stack are private per context.
* User image pages are currently private per context.
* Kernel-visible shared state must live in shared pages.
* Context switching is explicit and performed through BIOS/MMU entry points.
* The user image is loaded into CTX 0 for metadata access and into user contexts for execution.

---

## Boot Image Model

The kernel and user/test code are now split.

### Kernel image

`neox_kernel.rom` contains kernel code and kernel-owned boot policy code.

Kernel-side boot code:

```text
kernel/main.asm
    kernel initialization
    calls tasks_init

kernel/init_tasks.asm
    validates/reads user image table
    creates initial processes
    contains no user task bodies
```

### User image

`neox_user.rom` contains:

```text
USER_ENTRY   static user image boot table
USER_TEXT    user/test process code
USER_RODATA  user read-only data
USER_DATA    user initialized data
USER_BSS     user uninitialized data
```

The user image is loaded into each context that needs it:

```text
CTX 0  reads USER_ENTRY at $2000 during boot
CTX 1  executes PID 1 user image
CTX 2  executes PID 2 user image
CTX 3  executes PID 3 user image
```

Because `$2000` is private per context, CTX 0 must also receive `neox_user.rom` so the kernel can read the boot table.

### User image entry table

At the beginning of user space, the user image provides a small table:

```text
magic
version
task count
(context, flags/reserved, entry address)[]
```

The entry addresses are **virtual addresses**. The same virtual address is valid in each context that maps the user image.

Boot flow:

```text
1. RP2350 loads configured ROMs into contexts.
2. Kernel starts in CTX 0.
3. main.asm calls tasks_init.
4. tasks_init reads the user image table at $2000 in CTX 0.
5. tasks_init creates initial processes with the requested contexts and entry addresses.
6. Scheduler starts user processes in CTX 1..N.
```

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

`proc_signal_pending` is explicitly cleared during scheduler initialization and process creation, so newly-created or reused process slots do not inherit stale pending signals.

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

Pipes will add additional wait reasons for pipe read/write blocking.

---

## Synchronization Model

NEOX uses three distinct synchronization mechanisms. They are not interchangeable.

### Scheduler lock

```text
sched_lock
```

`sched_lock` is a scheduler policy gate. It prevents task switching while critical supervisor/monitor code is active.

It is not a general ownership lock and must not be converted to the generic lock mechanism.

### IRQ-critical sections

Very short scheduler or hardware transition sections may use:

```asm
php
sei
...
plp
```

This is reserved for small atomic transitions only.

### Generic subsystem locks

Generic locks are byte locks implemented through W65C02 `TSB` / `TRB` macros in `include/lock.inc`.

Current subsystem locks:

```text
fd_lock    protects FD/open-object table mutation
pipe_lock  reserved for pipe object/buffer state
rp_lock    protects RP mailbox ownership
```

Rules:

* Locks live in shared memory, not zero page.
* `LOCK_ACQUIRE` / `LOCK_RELEASE` clobber `A` and flags.
* Return values must be restored after releasing a lock.
* Do not hold `fd_lock` across device backend calls.
* Do not hold `pipe_lock` across blocking/yield.
* Do not spin on subsystem locks from the scheduler IRQ path.
* Do not convert `sched_lock` into a generic TSB/TRB lock.

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
* `rp_lock` uses the generic TSB/TRB lock mechanism.
* RP status checks remain part of the mailbox protocol.
* IRQ handlers must not use the RP mailbox path.
* IRQs are disabled only around small doorbell/status transition windows when needed.
* Long RP waits must not globally disable IRQs.

The asynchronous console read path may hold `rp_lock` while a console read transaction is pending. This is acceptable for the current console model but may need redesign when additional slow RP services are added.

---

## FD / Device Layer

The FD/device layer is separated from syscall argument decoding.

### Read/write path

```text
ksys_read / ksys_write
    -> decode syscall argument block
    -> fd_read / fd_write
        -> acquire fd_lock
        -> fd lookup for current process
        -> permission check
        -> open-object lookup
        -> object type check
        -> resolve operation pointer
        -> snapshot dispatch target
        -> release fd_lock
        -> device operation dispatch
            -> console_read / console_write
```

`fd_read` and `fd_write` release `fd_lock` before entering the backend. Device backends may block/yield.

### Close path

```text
ksys_close
    -> fd_close
        -> fd lookup for current process
        -> clear process fd entry
        -> clear process fd flags
        -> decrement open-object refcount
        -> call backend close when final reference is closed
```

### Tables

The current model uses:

```text
proc_fd_obj[pid][fd]     = open object index
proc_fd_flags[pid][fd]   = per-process fd permissions
open_type[obj]           = object type
open_refcnt[obj]         = reference count
open_flags[obj]          = open-object flags
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

## FD Duplication

`dup` and `dup2` are implemented and validated.

### `dup(oldfd)`

Behavior:

```text
find lowest free fd
copy fd flags from oldfd
attach new fd to same open object
increment open-object refcount
return new fd
```

### `dup2(oldfd, newfd)`

Behavior:

```text
validate newfd range
validate oldfd before modifying newfd
if oldfd == newfd, return newfd unchanged
if newfd is open, close it first
attach newfd to oldfd's open object
return newfd
```

Validated cases:

```text
dup(2) creates fd 3 and increments object 2 refcount
dup2(1,1) returns 1 and does not change refcounts
dup(3) fails EBADF when fd 3 is closed
dup2(3,1) fails EBADF and preserves fd 1
dup2(1,4) fails EBADF when MAX_FDS = 4
```

A current internal helper, `fd_close_current_locked`, exists for `dup2` so that `dup2` can close the target fd while already holding `fd_lock`. Before pipe close semantics are added, this should be generalized into a close-core that can report deferred close/wakeup actions.

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

| ID | Name  | Description                 |
| -- | ----- | --------------------------- |
| 3  | read  | read from file descriptor   |
| 4  | write | write to file descriptor    |
| —  | close | close a file descriptor     |
| —  | dup   | duplicate a file descriptor |
| —  | dup2  | duplicate to a specific fd  |
| —  | exit  | terminate current process   |
| —  | yield | voluntarily yield the CPU   |
| —  | sleep | block for timer ticks       |

The final syscall ID table is still evolving. The syscall ABI is fixed in structure, but the exported syscall set is still under active development.

### Calling convention

For argument-block syscalls:

```text
X/Y = pointer to args
C clear = success
C set   = error, Y = errno
A/X     = return value where applicable
```

For simple scalar syscalls such as close or dup:

```text
A = scalar argument
C clear = success
C set   = error, Y = errno
A/X     = return value where applicable
```

For `dup2`:

```text
A = old fd
Y = new fd
C clear = success, A = new fd
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

Pending signal state is initialized when process table slots are cleared and when new processes are created.

---

## Pipe Design Direction

Pipe implementation is the next major subsystem.

Planned staged implementation:

1. Define pipe constants and data structures.
2. Add pipe object allocation/free.
3. Add `pipe()` syscall to create read/write endpoints.
4. Add `pipe_read` and `pipe_write`.
5. Integrate `OBJ_PIPE` into FD read/write dispatch.
6. Integrate pipe endpoint close semantics into FD close.
7. Add blocking read when empty and writer exists.
8. Add blocking write when full.
9. Add close-end wakeups.

Initial semantics:

```text
pipe() creates two fds:
    read end  -> FD_FLAG_READ
    write end -> FD_FLAG_WRITE

read empty pipe:
    writers exist    -> block reader
    no writers exist -> EOF, return length 0

write pipe:
    readers exist    -> write bytes
    no readers exist -> EPIPE or EIO initially

close read end:
    mark reader closed
    wake blocked writers

close write end:
    mark writer closed
    wake blocked readers
```

Rules for pipe locking:

* `pipe_lock` protects pipe object and buffer state.
* Do not hold `pipe_lock` across `sched_yield`.
* Do not hold `fd_lock` while blocking on a pipe.
* Avoid holding `fd_lock` and `pipe_lock` together unless a strict order is defined.

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
* pending signal
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
user/     -> user/test code and user image entry table
```

Current split:

```text
kernel/main.asm        -> kernel boot sequence
kernel/init_tasks.asm  -> boot-time process creation from user image table
user/user_entry.asm    -> static user image table at start of user space
user/task*.asm         -> user/test task bodies
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
* RP2350 mailbox I/O with `rp_lock`
* FD read/write dispatch
* FD permission validation
* FD close and refcount decrement
* FD `dup` and `dup2`
* console device backend
* process termination cleanup path
* basic process-control signal infrastructure
* separate kernel/user images for boot-time test programs
* user image entry table at the beginning of user space

Validated behavior includes:

* console I/O through FD/device dispatch
* `write(0)` fails because stdin is read-only
* `read(1)` fails because stdout is write-only
* `close(1)` clears only the calling process' stdout
* `write(1)` fails after `close(1)`
* `write(2)` still works after stdout is closed
* `dup(2)` creates a second reference to stderr
* closing the original fd after `dup` leaves the duplicate working
* `dup2(1,1)` succeeds without changing refcounts
* invalid `dup` / `dup2` cases return `EBADF`
* final FD refcounts remain correct after duplication edge tests

---

## Next Steps

Near-term:

* freeze current FD/device/user-image checkpoint
* refactor close internals before pipe endpoint close semantics
* implement pipe object table and pipe endpoint objects
* add `pipe()` syscall
* add simple pipe read/write tests
* add blocking pipe read/write behavior

Later:

* filesystem layer
* richer device model
* executable loading / exec model
* init process model
* parent/child and wait/zombie semantics
* shared read-only user text pages with private data pages

---

## License

TBD
