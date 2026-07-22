# NEOX Software Signalling

This document covers process-level software signalling inside the 6502 kernel.
It does not cover RP-side physical 6502 control signals.

## Signal numbers

NEOX uses the corresponding Linux signal numbers for every currently
implemented process signal:

```text
2   SIG_INT
9   SIG_KILL
18  SIG_CONT
19  SIG_STOP
```

The public C definitions are `NEOX_SIG_INT`, `NEOX_SIG_KILL`,
`NEOX_SIG_CONT`, and `NEOX_SIG_STOP`.

`SIG_HALT` remains only as an assembly source-compatibility alias for
`SIG_STOP`.

## Current actions

```text
SIG_INT
    default: terminate with exit status $FE
    PROC_FLAG_SIGINT_INTERRUPT: interrupt console read with EINTR

SIG_KILL
    force target into ZOMBIE state
    cannot be caught or converted into EINTR

SIG_STOP
    stop a runnable process after it releases sleepable gates

SIG_CONT
    resume a stopped process
```

Signal delivery is serialized by `proc_gate`. A signal is never allowed to
strand a process while it owns `FILE_IO` or `PROC`. Default-action `SIG_INT`
uses the post-gate scheduler checkpoint so a verbose process cannot immediately
start another syscall after releasing its final gate.

## Public syscall boundary

```c
neox_status_t neox_signal(
    neox_pid_t pid,
    uint8_t signal);
```

The syscall accepts only signal numbers 2, 9, 18, and 19. PID 0, empty process
slots, zombies, and out-of-range PIDs are rejected.

## Shell command

The parent-mode `kill` applet accepts numeric signal syntax only:

```text
kill -2 PID
kill -9 PID
kill -18 PID
kill -19 PID
```

Named forms such as `-KILL` or `-STOP` are intentionally not implemented.
