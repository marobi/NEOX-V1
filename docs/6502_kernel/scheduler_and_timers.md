# Scheduler and Timers

NEOX is designed under a preemptive scheduling correctness model.

## Core rules

- `active_pid` is the authoritative running/interrupted PID inside the 6502 kernel.
- Global or module-local scratch is unsafe under preemption unless protected before first write and until last read.
- Valid protection is a real gate/lock, `SEI` around a proven no-preemption window, per-process/per-context storage, or a proven single-owner path.
- Code that cannot acquire a serialization gate or must wait for a condition must block/yield/retry rather than spin forever.
- Blocking code must release gates it owns before `sched_yield`.
- IRQ handlers must not enter mailbox/filesystem paths.

## Wait and wakeup

Blocking operations record a wait reason and yield. Wakeup paths clear or update wait state when the awaited condition becomes true.

Relevant wait classes include console input, pipe read/write, process wait, and gate/resource waits.

## Timer IRQ relationship

The RP side generates IRQs for the 6502. The 6502 kernel consumes timer IRQs as scheduling events. The RP side also tracks IRQ source and pending state in shared memory.

Timer expiry wake/resume behavior must be considered together with the RP context-switch request/acknowledgement path. Delayed VPB/IRQ acknowledgement can occur if RP-side context-switch handling falls into timeout/recovery.
