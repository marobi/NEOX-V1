# NEOX

NEOX is a small UNIX-like operating system for the **NEO6502_MMU** platform.

The system targets a W65C02 CPU with an RP2350 coprocessor. The 6502 side runs the kernel, scheduler, syscall layer, file-descriptor layer, pipe layer, monitor integration, and user tasks. The RP2350 side provides external I/O services, interrupt sources, console integration, raw monitor console I/O, and platform control.

NEOX is currently an experimental kernel, not a complete POSIX system. The design goal is to build a compact, understandable UNIX-like environment around processes, file descriptors, pipes, syscalls, and a monitor/debugger model suitable for a banked/MMU-enabled 6502 machine.

## Project Goals

NEOX is intended to provide:

- multiple 6502 tasks/processes
- cooperative and timer-driven preemptive scheduling
- a syscall interface
- per-process file descriptors
- shared open-object tables
- console I/O through the RP2350
- pipes for inter-process communication
- freeze-style monitor/debugger entry without corrupting kernel state
- a clear kernel structure that can grow toward a small UNIX-like system

The current implementation favors explicit, static kernel structures over dynamic allocation. This keeps the kernel easier to debug on real hardware and avoids unnecessary runtime complexity during bring-up.

## Platform Overview

The hardware model is:

```text
W65C02         main CPU running NEOX
RP2350         I/O, interrupt, raw monitor console, and platform coprocessor
MMU            multiple 6502 address contexts
SRAM           physical RAM behind the MMU
ROM images     BIOS, monitor, syscall veneer, and kernel
MICMON         monitor/debugger
```

The RP2350 communicates with the 6502 through shared mailbox/register mechanisms and interrupt sources.

There are two distinct RP/6502 I/O models:

```text
normal kernel I/O       syscall -> ksys_io -> FD/device -> RP mailbox
monitor raw I/O         BIOS raw get/put-char -> RP raw monitor path
```

The monitor raw I/O path is intentionally outside the normal kernel service model.

## Current Memory and Image Model

The current development layout uses separate statically linked images:

```text
$8000-$BFFF  Kernel
$C000-$CFFF  Syscall veneer
$D000-$DFFF  RP I/O page / shared platform registers
$E000-$EFFF  MICMON / monitor
$F000-$FFFF  BIOS
```

The current kernel model is statically linked. There is no relocatable user executable format yet.

The MMU model is central to the scheduler design:

```text
$0000-$7FFF  private per context
$8000-$FFFF  shared across contexts
```

This means zero page and the hardware stack page `$0100-$01FF` are private to the active context. Kernel code, shared state, BIOS, monitor, RP registers, and fixed ROM areas live in the shared upper half.

A later executable format may be added, but the present focus is kernel correctness, syscall behavior, process scheduling, IRQ/monitor behavior, and IPC.

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
supervisor      MICMON entry/exit and privileged control flow
irq             IRQ dispatch and timer/monitor interrupt handling
syscall table   fixed syscall entry points
FD layer        per-process FD table and global open-object table
device layer    device dispatch through open objects
console device  RP-backed normal console read/write
pipe layer      static pipe implementation
RP layer         normal mailbox / RP2350 request handling
BIOS            context switching, IRQ ACK, raw monitor get/put-char
```

The design avoids a relocatable runtime dependency. Kernel and syscall images are fixed-position binaries.

## Scheduler

NEOX supports both cooperative and preemptive scheduling.

Cooperative scheduling is available through `sys_yield`. Preemptive scheduling is driven by the timer IRQ when enabled.

The scheduler tracks:

```text
process state
saved stack pointers
MMU context IDs
wait reasons and wait objects
file-descriptor ownership
scheduler debug state
```

Only one PID should be `RUN` at a time.

The current scheduler baseline uses an explicit separation between the running process identity and scheduler selection state:

```text
active_pid       PID currently executing or interrupted
active_context   MMU/private context currently active
sched cursor     scheduler-private scan/selection state
```

This separation is required for preemptive scheduling. An IRQ can interrupt any task, so the interrupted task identity must not be confused with the scheduler's temporary scan cursor.

Context switch handoff follows this invariant:

```text
1. save old task stack pointer while still in the old private context
2. select target PID/context from shared scheduler state
3. execute BIOS_CONTEXT_SWITCH with the target context
4. only after the context switch, install the target stack with TXS
5. release sched_lock as late as possible
6. restore the target frame and resume with RTI, or JMP for first-run entry
```

The scheduler must not inspect or modify another task's private stack before switching to that task's context.

During freeze-monitor snapshots it is valid to observe transitional scheduler state, for example `SCHED` held while the marker shows a load/handoff phase. A healthy snapshot still has coherent `Active PID` / `Active Context`, one `RUN` task, sane wait/object tables, and no scheduler lock underflow.

## IRQ Model

IRQ entry saves the interrupted A/X/Y registers on the interrupted context stack.

IRQ source handling currently includes:

```text
timer IRQ       scheduler tick and optional preemptive context switch
monitor IRQ     immediate freeze-style entry into MICMON
other IRQ       restore interrupted context unchanged
```

The IRQ handler reads the RP IRQ source, acknowledges it through BIOS, and then classifies the source.

Timer IRQ behavior:

```text
monitor_active = 0:
    increment system_ticks through scheduler_irq_tick
    context-switch only when scheduler/subsystem locks allow it

monitor_active != 0:
    acknowledge and ignore timer IRQ
    do not increment system_ticks
    do not run scheduler accounting
    do not context-switch
```

This preserves freeze semantics while MICMON is active.

## RP IRQ Handshake

The current RP/6502 IRQ handshake is level/state based.

The working model is:

```text
RP:
    write RP_IRQ_SOURCE
    set RP_IRQ_STATE pending/asserted
    assert IRQ low

6502:
    read RP_IRQ_SOURCE
    call BIOS_ACK_IRQ

BIOS_ACK_IRQ:
    preserve A
    clear BIOS/RP IRQ source as the 6502 ACK
    wait until BIOS/RP IRQ state is released
    return with original A

RP:
    sees source cleared
    releases IRQ
    clears IRQ state
```

This avoids missed IRQ pulses when the 6502 has interrupts masked.

## Monitor Model

NEOX uses a **freeze-style monitor**.

The monitor is not a kernel task and does not participate in the syscall/FD/device/pipe/RP-mailbox model. Its purpose is to inspect the current system state exactly as it was frozen.

Monitor entry rules:

```text
monitor IRQ
    -> irq_entry
    -> BIOS_ACK_IRQ
    -> supervisor_enter_from_irq
    -> save current IRQ stack pointer and current context
    -> set monitor_active through console_monitor_enter
    -> switch to monitor context
    -> jump to MICMON

monitor leave
    -> console_monitor_exit
    -> clear monitor_active
    -> restore saved stack pointer and context
    -> return through irq_restore
    -> RTI to the interrupted code
```

The monitor may be entered while locks are held. This is intentional. Locks are part of the state being inspected.

MICMON uses BIOS low-level raw get/put-char routines only. These raw routines are separate from the normal kernel console and do not take kernel locks.

`monitor_active` is the authoritative software state for monitor mode. It is used to:

```text
freeze timer accounting in irq.asm
distinguish context 0 idle/kernel from context 0 MICMON
tell RP-side logic that raw monitor console mode is active
```

`current_context == 0` alone is not sufficient to detect MICMON, because context 0 can also be used by idle/kernel/common code. RP-side monitor handling should use a dedicated monitor-active state, not infer monitor mode only from the MMU context.

## BIOS Context Switching

The BIOS exposes the context switch primitive as an inline macro in `bios.inc`:

```text
BIOS_CONTEXT_SWITCH
```

This macro is deliberately stack-free. No `JSR`/`RTS` may cross an MMU/private-context switch because the return address would be on the previous context's private stack.

The macro only switches the private memory/MMU context. It does not restore registers, does not perform `RTI`, and does not jump into a task. Resume semantics belong to the scheduler or supervisor after the target context is active and the correct stack has been installed.

The old model of BIOS-owned context-switch-and-resume routines is not used by the scheduler baseline. The scheduler owns the final handoff sequence.

## BIOS Monitor I/O

BIOS provides raw monitor get/put-character routines for MICMON.

They communicate with RP through a dedicated low-level raw monitor console path.

This is a critical invariant. Earlier monitor designs could deadlock when MICMON output went through `sys_write`, because the monitor could interrupt a task that already owned the normal kernel I/O serialization path. The current monitor path stays outside `file_io_gate`, FD dispatch, and RP mailbox syscalls.

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

The intended model is syscall-layer blocking:

```text
ksys_read / ksys_write
    -> fd_read / fd_write
        -> pipe_read / pipe_write
    -> if EAGAIN:
        set wait state
        release locks
        yield
        retry later when woken
```

This keeps pipe backend primitives small, deterministic, and nonblocking.

## Inter-Process Pipe Tests

Current test wiring supports static inter-process pipes.

Example ping-pong setup:

```text
Pipe A: Task 1 -> Task 2
  PID 1 fd 3 = write endpoint
  PID 2 fd 3 = read endpoint

Pipe B: Task 2 -> Task 1
  PID 2 fd 4 = write endpoint
  PID 1 fd 4 = read endpoint
```

The current nonblocking ping-pong test uses `EAGAIN -> sys_yield -> retry`.

Observed ping-pong throughput around the first-freeze scheduler baseline:

```text
4 MHz class run:  lps ~= $0650  (about 1616)
8 MHz test run:   lps ~= $09C0  (about 2496)
```

These figures are development measurements, not final performance targets. They are useful mainly as regression indicators while scheduler, syscall, and pipe behavior are changed.

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
scheduler debug state
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

## Locking and Gate Policy

The kernel uses small shared lock/gate primitives for critical subsystems.

Current shared synchronization objects shown by `ps` are:

```text
SCHED     scheduler handoff lock
FILE_IO   sleepable gate for syscall FD/open-object/pipe/console dispatch
PROC      sleepable gate reserved for process-management serialization
RP        RP mailbox/resource lock
```

Important rules:

```text
Do not touch scheduler shared state without sched_lock or an IRQ-masked scheduler window.
Do not use global/module-local syscall scratch before the owning gate is acquired.
Do not use file_io_gate-protected scratch after file_io_gate_release.
Do not hold file_io_gate across sched_yield or an indefinite wait.
Do not hold rp_lock across an indefinite wait.
Do not spin indefinitely when a real serialization gate cannot be acquired.
Do not use normal kernel services from MICMON.
Every shared lock/gate byte must have one explicit initialization owner.
```

`file_io_gate` serializes file-descriptor lookup, open-object access, pipe table/buffer access, and the syscall read/write/close/pipe dispatch scratch that cannot be safely shared under preemption.

Monitor entry is allowed while locks or gates are held because MICMON uses raw BIOS monitor I/O only and must not acquire the inspected kernel locks.

## Scheduler and Debug Output

The `ps` monitor output includes compact scheduler and synchronization state.

Important fields:

```text
Active PID / Context     currently executing process identity and MMU context
Locks/Gates              SCHED, FILE_IO, PROC, RP ownership and phase state
Path / Marker            last scheduler path and handoff marker
Save PID/SP/Src          last saved task stack and source path
Load PID/SP              last loaded task stack
Resume PID/Ctx/Src       last resume target and context
IRQ preempt              IRQ preemption attempt/switch diagnostic snapshot
State change             last process state transition
```

`ps` may sample the kernel in the middle of a scheduler handoff. A held `SCHED` lock is therefore not automatically a deadlock. Interpret it together with the marker, active PID/context, selected PID, and lock underflow field.

Stale temporary diagnostics are intentionally kept out of the first-freeze baseline. Future useful counters may include committed cooperative switches, committed preemptive switches, and IRQ preemption attempts, but those are not part of the current freeze.

## First Freeze Baseline

The current stable source state is the first freeze baseline.

Confirmed characteristics:

```text
BIOS_CONTEXT_SWITCH is macro-only and stack-free
scheduler no longer depends on BIOS_CONTEXT_RTI/JUMP-style resume semantics
context switch happens before TXS or target stack access
sched_lock is released after context switch and target stack installation
monitor entry/leave works
console focus on task 3 works
ping-pong throughput is stable around lps=$0650 at the earlier baseline clock
8 MHz test reached about lps=$09C0
ps snapshots show sane FD/open-object/pipe tables
ps snapshots show one RUN task and SCHED underflow 00
```

Current working capabilities include:

- process switching
- cooperative `sys_yield`
- timer-driven preemptive scheduling when timer IRQ is enabled
- stable repeated freeze-style MICMON entry/leave
- FD tables and open objects
- console FD integration
- static nonblocking pipes
- inter-process pipes
- two-pipe ping-pong test using `EAGAIN` and `sys_yield`
- raw BIOS monitor I/O independent of syscalls and RP mailbox
- RP/6502 IRQ handshake that avoids missed IRQ pulses

The first freeze should be treated as the known-good scheduler/context-switch baseline before adding new diagnostics or larger subsystem changes.

## Assembly Conventions

The codebase targets W65C02 and ca65.

## Status

NEOX is under active development.

The current code is intended for bring-up, kernel design validation, and hardware testing. Interfaces and internal structures may still change as the scheduler, FD layer, pipe layer, syscall semantics, and monitor/RP integration mature.
