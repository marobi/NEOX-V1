# NEOX

NEOX is a small UNIX-like operating system for the **NEO6502_MMU** platform.

The system targets a W65C02 CPU with an RP2350 coprocessor. The 6502 side runs the kernel, scheduler, syscall layer, file-descriptor layer, pipe layer, monitor integration, and user tasks. The RP2350 side provides external I/O services, interrupt sources, console integration, and platform control.

NEOX is currently an experimental kernel, not a complete POSIX system. The design goal is to build a compact, understandable UNIX-like environment around processes, file descriptors, pipes, syscalls, and a monitor/debugger model suitable for a banked/MMU-enabled 6502 machine.

## Project Goals

NEOX is intended to provide:

- multiple 6502 tasks/processes
- preemptive and cooperative scheduling
- a syscall interface
- per-process file descriptors
- shared open-object tables
- console I/O through the RP2350
- pipes for inter-process communication
- monitor/debugger entry without corrupting kernel state
- a clear kernel structure that can grow toward a small UNIX-like system

The current implementation favors explicit, static kernel structures over dynamic allocation. This keeps the kernel easier to debug on real hardware and avoids unnecessary runtime complexity during bring-up.

## Platform Overview

The hardware model is:

```text
W65C02        main CPU running NEOX
RP2350        I/O, interrupt, console, monitor, and platform coprocessor
MMU           multiple 6502 address contexts
SRAM          physical RAM behind the MMU
ROM images    BIOS, monitor, syscall veneer, and kernel
```

The RP2350 communicates with the 6502 through shared mailbox/register mechanisms and interrupt sources.

## Current Memory and Image Model

The current development layout uses separate statically linked images:

```text
$8000-$BFFF  Kernel
$C000-$CFFF  Syscall veneer
$D000-$DFFF  RP I/O page
$E000-$EFFF  MICMON / monitor
$F000-$FFFF  BIOS
```

The current kernel model is statically linked. There is no relocatable user executable format yet.

A later executable format may be added, but the present focus is kernel correctness, syscall behavior, process scheduling, and IPC.

## Toolchain

The kernel is built with:

```text
ca65     assembler
ld65     linker
make     build orchestration
```

The codebase is written in W65C02 assembly.

## Kernel Structure

The kernel is organized around small subsystems:

```text
scheduler       process switching, task state, wait state
supervisor      monitor entry/exit and privileged control flow
irq             IRQ dispatch and timer/monitor interrupt handling
syscall table   fixed syscall entry points
FD layer        per-process FD table and global open-object table
device layer    device dispatch through open objects
console device  RP-backed console read/write
pipe layer      static pipe implementation
RP layer         mailbox / RP2350 request handling
```

The design avoids a relocatable runtime dependency. Kernel and syscall images are fixed-position binaries.

## Scheduler

NEOX supports both cooperative and preemptive scheduling.

Preemptive scheduling is driven by the timer IRQ when enabled. Cooperative scheduling is available through `sys_yield`.

The current scheduler tracks process state, saved stack pointers, context IDs, wait reasons, and file-descriptor ownership.

PID 0 is reserved for the idle/supervisor role and is not treated as a normal user process.

## Monitor Entry

Monitor entry is deferred and cooperative.

The IRQ handler does **not** enter MICMON directly. A monitor IRQ only records a pending monitor request:

```text
RP monitor IRQ
    -> irq_entry
    -> monitor_pending = 1
    -> RTI
```

Actual monitor entry happens later from a safe cooperative kernel point, currently through `sched_yield`:

```text
sched_yield
    -> supervisor_try_enter_pending
    -> supervisor_monitor_safe
    -> enter_monitor
```

This is an intentional implementation decision.

Earlier direct monitor entry from IRQ was unsafe because MICMON uses console, FD, and RP paths. If an IRQ entered MICMON while the interrupted task held one of the related locks, the monitor could re-enter the same subsystem and deadlock on a lock owned by the frozen task.

The safe monitor-entry check currently requires these locks to be clear:

```text
sched_lock == 0
fd_lock    == 0
pipe_lock  == 0
rp_lock    == 0
```

If any lock is held, the monitor request remains pending and is retried at a later safe point.

This means that with the timer disabled, a CPU-bound task that never calls `sys_yield` or a syscall may delay monitor entry indefinitely. This is accepted for the current cooperative-safe monitor model.

## Syscall Model

The syscall layer is currently implemented as a fixed veneer/jump-table style interface rather than a dynamic runtime ABI.

Current syscall work includes:

- read
- write
- yield
- sleep
- pipe
- close
- duplication / FD management work
- tick/time-related test support

The current priority is correctness of the kernel-side semantics, not POSIX completeness.

## File Descriptors

NEOX uses per-process file-descriptor tables backed by a shared global open-object table.

A process FD points to an open object. Open objects represent devices, pipes, or other future object types.

Example:

```text
PID 1 fd 3 -> open object 4, write endpoint
PID 2 fd 3 -> open object 3, read endpoint
```

FD numbers are local to a process. The same FD number in two processes can refer to different open objects.

The FD layer owns:

```text
per-process FD tables
global open-object table
open-object type
open-object flags
open-object refcount
open-object backend reference
```

The FD table and open-object table are shared kernel state.

FD temporary scratch variables belong in `fd.asm` `KERN_BSS`. The zero-page FD pointer is kept only where indirect-indexed addressing requires it.

## Pipes

The current pipe implementation is static and nonblocking at the backend layer.

Pipe endpoints are represented by open objects:

```text
read endpoint  -> open object
write endpoint -> open object
both reference the same pipe index
```

The pipe backend implements:

```text
pipe_read:
    empty + writers present -> EAGAIN
    empty + no writers      -> EOF
    data available          -> read bytes

pipe_write:
    no readers              -> EPIPE
    full + zero progress    -> EAGAIN
    full + some progress    -> short write
    space available         -> write bytes
```

The pipe core does not block internally and does not call `sched_yield`.

This is an explicit decision. A previous attempt to block inside `pipe_read` / `pipe_write` was rejected because it required preserving pipe-local call state across a context switch and introduced unsafe lock/wait interactions.

The intended future model is syscall-layer blocking:

```text
ksys_read / ksys_write
    -> fd_read / fd_write
        -> pipe_read / pipe_write
    -> if EAGAIN:
        set wait state
        yield
        retry later
```

This keeps pipe backend primitives small, deterministic, and nonblocking.

## Inter-Process Pipe Tests

Current test wiring supports static inter-process pipes.

Example ping-pong setup:

```text
Pipe A: Task 1 -> Task 2
  PID 1 fd 3 = write
  PID 2 fd 3 = read

Pipe B: Task 2 -> Task 1
  PID 2 fd 4 = write
  PID 1 fd 4 = read
```

The current nonblocking ping-pong test uses `EAGAIN -> sys_yield -> retry`.

Observed 10-second loop baselines during development were approximately:

```text
loops10 ~= $0700 .. $08A0
```

These figures are development measurements, not final performance targets.

## Shared State and Scratch Policy

The kernel separates durable shared state from subsystem-private scratch.

`shared_state.asm` is reserved for state that is genuinely shared, ABI-visible, monitor-visible, or externally inspectable, such as:

```text
process tables
FD/open-object tables
pipe tables and buffers
locks
monitor state
RP-visible state
```

Subsystem-private scratch belongs in the owning module’s `KERN_BSS`.

Examples:

```text
fd_ptr        -> zero page, because it is used for indirect addressing
pipe_ptr      -> zero page, user buffer pointer
pipe_buf_ptr  -> zero page, pipe buffer pointer

fd_pid_tmp    -> fd.asm KERN_BSS
fd_index_tmp  -> fd.asm KERN_BSS
fd_obj_tmp    -> fd.asm KERN_BSS

pipe_obj      -> pipe.asm KERN_BSS
pipe_idx      -> pipe.asm KERN_BSS
pipe_req_lo   -> pipe.asm KERN_BSS
pipe_req_hi   -> pipe.asm KERN_BSS
pipe_done_lo  -> pipe.asm KERN_BSS
pipe_done_hi  -> pipe.asm KERN_BSS
```

Zero page is used only where it materially helps addressing or performance. General temporary variables, counters, IDs, and flags should not be placed in zero page by default.

## Locking Policy

The kernel uses simple shared lock bytes for critical subsystems.

Important rules:

```text
Do not hold fd_lock across backend calls.
Do not hold pipe_lock across sched_yield or blocking waits.
Do not enter MICMON directly from IRQ.
Do not spin in IRQ/scheduler paths on FD, pipe, or RP locks.
Every lock byte must have one explicit initialization owner.
```

The current monitor design exists largely to preserve these rules.

## Current State

The current working baseline includes:

- process switching
- cooperative `sys_yield`
- timer-driven scheduling when timer IRQ is enabled
- deferred monitor entry through `monitor_pending`
- FD tables and open objects
- console FD integration
- static nonblocking pipes
- inter-process pipe wiring for test tasks
- two-pipe ping-pong test using `EAGAIN` and `sys_yield`
- cleanup of FD and pipe scratch into module-local `KERN_BSS`
- monitor IRQ path no longer directly entering MICMON

The next major implementation step is expected to be syscall-layer blocking for pipes, not blocking inside the pipe backend.

## Assembly Conventions

The codebase targets W65C02 and ca65.

Coding rules used in the kernel:

```text
Use valid W65C02 addressing modes only.
Do not use invalid forms such as LDX abs,X.
Use JMP for tail calls instead of JSR followed immediately by RTS.
Keep stack-frame and lock-sensitive routines explicit and commented.
Prefer complete procedure replacements for complex scheduler/lock/wait changes.
```

Example tail-call rule:

```asm
; Avoid
jsr routine
rts

; Use
jmp routine
```

## Status

NEOX is under active development.

The current code is intended for bring-up, kernel design validation, and hardware testing. Interfaces and internal structures may still change as the scheduler, FD layer, pipe layer, and syscall semantics mature.
