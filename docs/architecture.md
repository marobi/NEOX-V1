# Architecture

NEOX is a small operating environment for the NEO6502_MMU platform. It borrows useful Unix-like ideas, but it is not intended to become a full Unix clone.

## Design principles

- The 6502 side owns the NEOX software model: processes, scheduling state, file descriptors, pipes, cwd, syscalls, shell policy, and applet execution.
- The RP side owns hardware-facing services: USB host, keyboard and mouse input, USB MSC/FatFs storage, VDU rendering, mailbox dispatch, transparent memory access, and 6502 hardware control.
- The RP side may observe, halt, clock, interrupt, reset, and debug the 6502 machine from outside the NEOX process model.
- That out-of-band authority must not be confused with normal NEOX process signalling or syscalls.

## Not a fork-first design

NEOX does not start with full Unix `fork`. The first execution model is resident/preloaded spawn:

1. The kernel allocates a child process and a preloaded user context.
2. The parent configures child stdio, cwd, launch id, and launch arguments.
3. The parent commits the child.
4. The child runs a resident entry such as `nbox_child_entry`.
5. The parent may wait and reap the child with `waitpid`.

External executable loading from disk can be added later using the same process/fd/wait/exit machinery. The difference will be how the child image is prepared before commit.

## RP authority versus NEOX authority

The RP side has physical authority over the machine:

- 6502 clock generation
- reset/run/halt control
- single-cycle and single-step execution
- IRQ generation
- MMU/context control interaction
- transparent memory access
- debugger and disassembler access

The NEOX kernel has software authority inside the 6502 execution model:

- process state
- fd tables
- pipes
- cwd
- wait/reap
- process signalling
- syscall-visible behavior

These are deliberately separate layers.


## Monitor distinction

The system has two monitor/debug concepts that must be kept separate:

```text
RP-side MicMon/control monitor
  Out-of-band machine controller on the RP side.
  Controls reset/run/halt, clock, IRQ generation, transparent memory access, and RP diagnostics.

6502 MicMon monitor
  In-band W65C02 machine monitor running as 6502 code.
  Provides BRK/warm monitor entry, saved-register editing, memory dump/edit, GO, disassembly, and one-line assembly.
```

Both are machine-level tools. Neither is the NEOX shell, and neither should be documented as a normal user process.
