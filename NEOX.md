# NEOX — Current Architecture

NEOX is a minimal UNIX-like OS for the NEO6502-MMU platform: a W65C02 runs kernel/user code, while the RP2350 provides MMU switching and mailbox-based I/O.

## Layout

| Area          | Role                                |
| ------------- | ----------------------------------- |
| Context 0     | MICMON / supervisor, not scheduled  |
| Contexts 1..N | scheduled processes                 |
| Pages 0–7     | private ZP/stack/RAM per context    |
| Pages 8–F     | shared RAM, I/O, kernel, BIOS       |
| `$C000`       | syscall veneer, fixed ABI JMP stubs |
| `$E000`       | kernel implementation               |

## Scheduler / Processes

The scheduler is timer-IRQ driven, preemptive, and round-robin. Process states are:

```text
EMPTY → NEW → RUNNING ↔ READY
             ↘ BLOCKED
```

`sched_lock != 0` freezes scheduling. It is used for monitor execution and short critical kernel sections; it is not a mutex.

## Syscall / FD / Device Path

The syscall page is only an ABI veneer. Real implementation lives in the kernel:

```text
sys_read/sys_write → ksys_read/ksys_write
    → fd_lookup
    → dev_resolve_op
    → console_read/console_write
    → RP2350 mailbox backend
```

Syscall convention:

```text
X/Y = argument pointer
C clear = success, A/X = return value
C set   = error,   Y = errno
```

## Console Invariants

```text
RP_CONSOLE_PID    = RP/user requested focus; 6502 never writes it
console_owner_pid = kernel-accepted foreground process
console_wait_pid  = process blocked on console input, or $FF
RP_CONSOLE_RDY    = input available flag
```

Rules:

```text
Only console_owner_pid may consume fd 0 input.
Non-owner read returns 0.
Owner + no input → process BLOCKED, console_wait_pid = owner.
Owner + input    → rp_console_read.
If console_wait_pid != $FF, it must equal console_owner_pid.
Scheduler wakes console_wait_pid when RP_CONSOLE_RDY != 0, then clears it.
```

## Monitor / MICMON

MICMON runs in context 0 and is not a process. Entering monitor freezes scheduler state; leaving monitor unfreezes it.

```text
enter: save SP, sched_lock_enter, jump monitor
leave: sched_lock_leave, restore SP, return via RTI/RTS path
```

Monitor must not modify:

```text
current_pid, proc_state, console_owner_pid, console_wait_pid, RP_CONSOLE_PID
```

## Current Status

Stable: context switching, round-robin scheduling, syscall veneer, FD/device dispatch, console ownership, blocking/wake, RP mailbox I/O, and MICMON monitor roundtrip.

Next: generalize blocking beyond console (`wait_reason` / wait object), extend device model, add process-control syscalls, then filesystem support.
