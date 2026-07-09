# NEOX Software Signalling

This document covers process-level software signalling inside the 6502 kernel. It does not cover RP-side physical 6502 control signals.

## Terminology

```text
NEOX signal
  software/process signal inside the 6502 kernel

RP 6502 control signal
  physical/debug control from the RP side, such as IRQ, reset, halt, or clocking
```

These are different subsystems.

## Current model

The process table contains compact signal-related state such as pending signal information. Signal state is visible in process diagnostics.

Signal delivery must obey the scheduler/preemption model. It must not corrupt process state, fd state, pipe state, or mailbox state.

## Rules

- Signal handling must not use filesystem/mailbox paths from IRQ context.
- Signal delivery must respect process ownership and lifecycle state.
- Signal state must interact cleanly with `PROC_ZOMBIE` and exit handling.
- A process that has already exited should not be treated as a normal signal target.

## Future work

The intended model should later define:

- available signal numbers
- default signal actions
- signal masks if needed
- signal delivery points
- interaction with blocking syscalls
- process group or child signalling policy if required
