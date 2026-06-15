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

## Blocking Model

Blocking is implemented by the syscall layer, not by low-level device or pipe backend primitives. The general pattern is:

```text
try operation
if the operation would block:
    set process wait reason and wait object
    release any sleepable gate owned by the syscall
    call sched_yield
    retry after the process is woken
```

Current blocking wait reasons validated in this checkpoint:

```text
WAIT_TIMER        sys_sleep / timer wake
WAIT_CONSOLE      console read with no input available
WAIT_PIPE_READ    pipe read on an empty pipe while writers still exist
WAIT_PIPE_WRITE   pipe write on a full pipe while readers still exist
```

Console and pipe blocking both follow the same critical rule:

```text
never block while holding FILE_IO
```

`WAIT_CONSOLE` uses `wait_object = 0` for the console input wait. `WAIT_PIPE_READ` uses `wait_object = pipe index`, so the writer can wake readers waiting on the same pipe. `WAIT_PIPE_WRITE` also uses `wait_object = pipe index`, so the reader can wake writers waiting for space on the same pipe.

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

The current pipe implementation is static. The pipe backend itself remains nonblocking; blocking semantics are implemented at the syscall layer.

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

This is intentional. Blocking inside `pipe_read` / `pipe_write` would require preserving pipe-local call state across a context switch and would mix backend state with scheduler wait logic. Instead, the syscall layer owns retryable blocking:

```text
ksys_read
    -> fd_read
        -> pipe_read
    -> if pipe read returns EAGAIN and writers are still present:
        save/read syscall arguments from the per-PID snapshot
        set WAIT_PIPE_READ / wait_object = pipe index
        release FILE_IO
        sched_yield
        retry the read after wake

ksys_write
    -> fd_write / pipe_write
    -> if pipe is full and readers exist:
        set WAIT_PIPE_WRITE
        release FILE_IO
        sched_yield
        retry the write after wake
    -> wakes readers blocked on the written pipe
```

The important invariant is that a process blocked on a pipe must not own `FILE_IO`. `ps` should show blocked pipe readers as `BLK PIP <pipe-index>` and blocked pipe writers as `BLK PIW <pipe-index>` with `FILE_IO` free.

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

Task simplification after blocking
----------------------------------

Blocking `read` / `write` syscalls now own the internal `EAGAIN` retry path. User tasks no longer need to poll `EAGAIN` and call `sys_yield` for console or pipe I/O. The sample ping-pong tasks and console echo task use normal blocking syscall style and only handle EOF, short transfer, or real errors.

The current blocking checkpoint no longer relies on userspace polling for empty pipe reads. Empty pipe reads with writers present block in `ksys_read` as `WAIT_PIPE_READ`; a later pipe write wakes the blocked reader. Full pipe writes with readers present block in `ksys_write` as `WAIT_PIPE_WRITE`; a later pipe read wakes the blocked writer.

Observed ping-pong throughput checkpoints:

```text
First freeze, 4 MHz:          lps ~= $0650  (about 1616)
WAIT_CONSOLE, 4 MHz:          lps ~= $0780  (about 1920)

First freeze, 8 MHz:          lps ~= $09C0  (about 2496)
WAIT_CONSOLE, 8 MHz:          lps ~= $09B0  (about 2480)
WAIT_PIPE_READ, 8 MHz:        lps ~= $0CF0  (about 3312)
WAIT_PIPE_WRITE + simplified tasks, 8 MHz: lps ~= $0A50  (about 2640)
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

The `ps` monitor output is intentionally compact in the current checkpoint. It is meant to show enough state to validate scheduler, wait, FD, and pipe correctness without disturbing timing more than necessary.

Important fields:

```text
Active PID / Context     currently executing process identity and MMU context
Console Owner PID        current console input owner, or 255 when unowned
Locks/Gates              SCHED, FILE_IO, PROC, RP ownership and phase state
Process table            PID state, stack pointer, context, wait reason/object, FD table
PID ticks                coarse runtime sampling per PID
```

`ps` may sample the kernel in the middle of a scheduler handoff. A held `SCHED` lock is therefore not automatically a deadlock. A healthy snapshot has coherent `Active PID` / `Active Context`, one `RUN` task, sane wait objects, free sleepable gates for blocked tasks, and `SCHED` underflow `00`.

Stale temporary diagnostics are intentionally kept out of the freeze baseline. Future useful counters may include committed cooperative switches, committed preemptive switches, IRQ preemption attempts, and run-selection counts per PID.

## Freeze Baselines

### First Freeze

The first freeze is the known-good scheduler/context-switch baseline.

Confirmed characteristics:

```text
BIOS_CONTEXT_SWITCH is macro-only and stack-free
scheduler no longer depends on BIOS_CONTEXT_RTI/JUMP-style resume semantics
context switch happens before TXS or target stack access
sched_lock is released after context switch and target stack installation
monitor entry/leave works
console focus on task 3 works
ping-pong throughput is stable around lps=$0650 at 4 MHz
8 MHz test reached about lps=$09C0
ps snapshots show sane FD/open-object/pipe tables
ps snapshots show one RUN task and SCHED underflow 00
```

The first freeze should be treated as the known-good scheduler/context-switch baseline before adding blocking semantics or larger subsystem changes.

### Current Blocking Freeze

The current freeze builds on the first freeze and adds validated syscall-layer blocking for console reads and pipe reads.

Confirmed characteristics:

```text
WAIT_TIMER already present through sys_sleep / timer wake
WAIT_CONSOLE validated
WAIT_PIPE_READ validated
console task blocks as BLK CON without holding FILE_IO
pipe readers block as BLK PIP <pipe-index> without holding FILE_IO
pipe write wakes blocked pipe readers
compact ps output is used for normal validation
SCHED underflow remains 00
FD/open-object/pipe tables remain sane
one real task is RUN while other tasks may be blocked on CON/PIP
8 MHz ping-pong with WAIT_PIPE_READ reached about lps=$0CF0
```

Current working capabilities include:

- process switching
- cooperative `sys_yield`
- timer-driven preemptive scheduling when timer IRQ is enabled
- stable repeated freeze-style MICMON entry/leave
- FD tables and open objects
- console FD integration
- `WAIT_CONSOLE` for console read blocking
- static pipe backend with syscall-layer `WAIT_PIPE_READ`
- inter-process pipes
- two-pipe ping-pong test using blocking pipe reads
- raw BIOS monitor I/O independent of syscalls and RP mailbox
- RP/6502 IRQ handshake that avoids missed IRQ pulses

Pipe write blocking is intentionally not part of this freeze yet.

## Assembly Conventions

The codebase targets W65C02 and ca65.

## Status

NEOX is under active development.

The current code is intended for bring-up, kernel design validation, and hardware testing. Interfaces and internal structures may still change as the scheduler, FD layer, pipe layer, syscall semantics, and monitor/RP integration mature.


Stale-code cleanup after blocking freeze
----------------------------------------

After the blocking freeze, stale userspace `EAGAIN` retry/yield loops were removed from the sample tasks. Obsolete BIOS scratch state from the former BIOS-owned context-jump model was removed. Unused imports and unused zero-page scratch reservations were removed from kernel modules. The compact debug/`ps` state was intentionally kept.

### RTI-only resume cleanup

The per-process `proc_resume_mode` table has been removed. The scheduler no longer selects between resume mechanisms per process: all normal saved runnable task frames are RTI-compatible. The idle and first-run paths remain explicit scheduler paths, not per-process resume modes. Compact scheduler debug still keeps its source/mode fields for diagnostics only.

### PROC gate lifecycle serialization

Process lifecycle entry points now use the explicit `PROC` gate where appropriate:

- `proc_create` acquires `proc_gate` before scanning/initialising a process slot and releases it after publishing or failing.
- `proc_exit_current` acquires `proc_gate` before terminating the active process and releases it before entering `sched_yield`.
- `proc_terminate` remains the low-level termination primitive. Internal scheduler-owned paths may call it directly where they already run under scheduler control.

`PROC` gate is not held across `sched_yield`.

## No-sleep pingpong checkpoint

The asymmetric timer-pingpong experiment is not part of this checkpoint.
Task 1 and task 2 again test blocking pipe read/write only; they do not call
`sys_sleep` in the normal pingpong loop. Their failure stop loops also avoid
`sys_sleep` while the timer/sleep IRQ-latency path is under review.

`sys_sleep` / `WAIT_TIMER` remains implemented in the kernel, but it is not
exercised by the normal task 1 / task 2 pingpong workload in this package.

## Timer sleep redesign checkpoint

`sys_sleep` now uses a scheduler-owned blocking transition instead of the old split model where `timer_start_current` marked the process blocked and `ksys_sleep` later entered `sched_yield`.

Current timer sleep model:

- `timer_start_current` arms a timer slot for `active_pid` and returns the timer slot in `Y`.
- `sched_block_current` owns the actual blocking transition.
- `sched_block_current` validates the armed timer slot before saving the syscall continuation.
- The syscall continuation is saved as the standard RTI-compatible frame.
- `WAIT_TIMER` and `wait_object = timer slot` are committed only after the continuation has been saved.
- `scheduler_wake_timers` now wakes a process only when `wait_object[pid]` matches the expired timer slot.
- Expired non-matching timer slots are treated as stale and freed without waking a process.
- No `TIMER_RESERVED` state is used.

This keeps one clear owner for the process block transition and avoids blocking a process on a timer slot that has already expired or been freed.

## Timer sleep commit cleanup

`timer_commit_current` now verifies that the armed timer slot is still pending before `sched_block_current` commits `WAIT_TIMER`. If the timer has already elapsed between arming and block commit, the slot is freed and `sys_sleep` returns success immediately instead of blocking on an already-due timer.

No debug output was added.
