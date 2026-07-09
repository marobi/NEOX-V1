# Transparent Memory Access

Transparent memory access means the RP reads or writes 6502-visible memory outside the 6502 CPU execution path.

## Access classes

```text
Class 1: Halted access
  6502 stopped/reset/halted. RP reads/writes are safe from CPU concurrency.

Class 2: Passive live read
  6502 running. RP reads memory for diagnostics. Snapshot may be inconsistent.

Class 3: Protocol-protected live access
  6502 running. RP and 6502 communicate through defined mailbox/queue/shared-state protocol.

Class 4: Unsafe live write
  6502 running. RP writes arbitrary live memory. This is invasive debugger/emergency behavior only.
```

## Monitor/debug use

MicMon memory dump and disassembly are normally observational. Memory modification is invasive and must be treated as explicit debug intervention.

## MMU/context interaction

The RP may select contexts for inspection or setup. When changing MMU maps or bus ownership, it must place the machine in an appropriate RP-controlled or halted state.

## Rule

Kernel/shared-state inspection is a diagnostic snapshot, not a synchronized transaction unless a specific protocol says otherwise.
