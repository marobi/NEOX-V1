# RP Mailbox Bridge

The RP mailbox bridge is the central service dispatcher between 6502 requests and RP-side service modules. It is not exclusive to filesystem service.

## Central dispatcher

`mailbox.cpp` owns:

- request/result block initialization
- doorbell trigger handling
- central command table
- group/command lookup
- status/result helpers
- error completion
- mailbox diagnostics

Current command families:

```text
console.*
fs.*
```

The grouped ABI also reserves system command space.

## Console service

Console mailbox commands handle console read/write. Some console transfers are long-running and advance through the mailbox FSM rather than completing in one immediate step.

## Filesystem service

Filesystem mailbox commands call RP filesystem/mailbox handlers and operate on RP-side file/directory handles.

## FSM

Current mailbox FSM states:

```text
mbINIT
mbIDLE
mbWRITE
mbREAD
mbDONE
```

The dispatcher updates `RP_CONSOLE_RDY`, consumes doorbell-triggered requests, dispatches the command by group/cmd, advances long-running console reads/writes, and returns to idle after completion.

## Safety rules

- Mailbox service is task/syscall-level service, not IRQ-context service.
- IRQ handlers must not enter filesystem/mailbox paths.
- RP receives explicit resolved paths for filesystem commands; it does not own process cwd semantics.
- The central mailbox table should remain the single command dispatch point.
