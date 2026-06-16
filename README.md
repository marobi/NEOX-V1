# NEOX / NEO6502_MMU

NEOX is a small experimental UNIX-like kernel for the NEO6502_MMU platform.

Target model:

```text
W65C02      kernel, scheduler, syscalls, FD/pipe/process state
RP2350      console I/O, IRQ source handling, monitor/debug support
ca65/ld65   assembler/linker toolchain
MICMON      freeze-style monitor/debugger
```

The current kernel uses statically linked images. There is no relocatable executable format yet.

## Current checkpoint

This source tree is the current stable checkpoint after signal and zombie-process validation.

Validated:

```text
preemptive scheduling
idle task
WAIT_CONSOLE
WAIT_PIPE_READ
WAIT_PIPE_WRITE
WAIT_TIMER
multiple concurrent timer sleeps
file I/O gate behavior
process gate behavior
RP gate behavior
SYS_SIGNAL = $12
SIG_HALT / SIG_CONT scheduler-safe handling
SIG_KILL -> PROC_ZOMBIE -> idle reaper -> PROC_EMPTY
normal pipe test restored and regression-passed
```

Healthy monitor snapshots should show:

```text
SCHED underflow = 00
FILE_IO free when tasks are idle/blocked
PROC free
RP free
no stale wait objects
no unexpected pending signals
```

## Memory and image model

Current linked image layout:

```text
$8000-$BFFF  Kernel
$C000-$CFFF  Syscall veneer
$D000-$DFFF  RP I/O / platform registers
$E000-$EFFF  MICMON / monitor
$F000-$FFFF  BIOS
```

MMU model:

```text
$0000-$7FFF  private per context
$8000-$FFFF  shared kernel / ROM / platform space
```

Zero page and stack page `$0100-$01FF` are private to the active context. Kernel code and shared kernel state live in the shared upper address space.

## Build

Build with:

```sh
make clean
make
```

Kernel entry table note:

```text
KENTRY size = $0060
entry size  = 3 bytes
slots       = 32
```

When adding a kernel entry-table `jmp`, replace one trailing `.res 3, $00`. Do not grow the table accidentally.

## Source layout

```text
bios/       BIOS, IRQ ACK, context-switch support
include/    shared constants and ABI definitions
kernel/     kernel subsystems
user/       active user test tasks
user/save_pipe_test/    saved pipe regression task set
user/save_signal_test/  saved signal/zombie validation task set
```

Active default tasks are the pipe regression tasks in `user/`.

## Scheduler model

The scheduler separates the currently executing process from scheduler scan state:

```text
active_pid       PID currently executing or interrupted
active_context   active MMU/private context
scheduler cursor private scheduler scan state
```

Context-switch invariant:

```text
save old stack in old context
select target PID/context
switch MMU context with BIOS_CONTEXT_SWITCH
then install target stack with TXS
release sched_lock late
resume target frame
```

The scheduler picker must only select runnable processes. It must not perform destructive cleanup.

## Wait states

Current wait model includes:

```text
WAIT_CONSOLE
WAIT_PIPE_READ
WAIT_PIPE_WRITE
WAIT_TIMER
WAIT_LOCK
```

Wake invariant:

```text
Only PROC_BLOCKED may be woken to PROC_READY.
PROC_STOPPED resumes only through SIG_CONT.
PROC_ZOMBIE must never be woken back to READY.
```

## Signals

Signals are represented by `proc_signal_pending[pid]`.

Current signals:

```text
SIG_NONE = $00
SIG_HALT = $01
SIG_CONT = $02
SIG_KILL = $03
```

User syscall:

```asm
lda #SIG_HALT      ; signal
ldx #$02           ; target PID
jsr sys_signal     ; SYS_SIGNAL = $12
```

Signal behavior:

```text
SIG_HALT:
  runnable task -> PROC_STOPPED
  blocked task  -> signal remains pending until the task wakes

SIG_CONT:
  PROC_STOPPED -> PROC_READY
  clears wait state

SIG_KILL:
  target -> PROC_ZOMBIE
  idle reaper -> proc_terminate -> PROC_EMPTY
```

The scheduler signal phase handles only lightweight state changes. It must not call `proc_terminate`.

## Zombie reaper

Killed processes are first marked:

```text
PROC_ZOMBIE = $06
```

The idle task calls the zombie reaper. The reaper performs destructive cleanup outside the scheduler picker/signal phase:

```text
close FDs
clear wait state
clear signal state
mark PROC_EMPTY
```

This keeps FD cleanup and gate usage out of scheduler-critical paths.

## Gates and locks

Current gate/lock model:

```text
SCHED    scheduler lock
FILE_IO  file/pipe/device syscall serialization
PROC     process-management serialization
RP       RP mailbox serialization
```

Rules:

```text
Do not block indefinitely while holding FILE_IO, PROC, or RP.
Do not call destructive process cleanup from sched_pick_next.
Do not use the RP mailbox path from IRQ handlers.
```

## Monitor/debug model

The monitor is a freeze-style debugger, not a kernel task.

Monitor path uses raw BIOS/RP monitor I/O and is separate from normal kernel console I/O:

```text
normal I/O   syscall -> FD/device/pipe -> RP mailbox
monitor I/O  BIOS raw get/put-char -> RP raw monitor path
```

`debug_neox.cpp` is the current RP monitor/debug source.

## Current test sets

Default active test:

```text
user/task1.asm
user/task2.asm
user/task3.asm
user/user_entry.asm
user/user_space.asm
```

Saved task sets:

```text
user/save_pipe_test/      pipe/console/timer regression
user/save_signal_test/    HALT/CONT/KILL/zombie validation
```

To switch tests manually, copy the wanted saved files back into `user/` and rebuild.

## Current design boundaries

Not implemented yet:

```text
relocatable executable format
full POSIX signals
signal handlers
waitpid/reparenting semantics
dynamic process allocation
filesystem
```

Do not add these until the current scheduler/process/FD/pipe baseline remains stable across regression tests.
