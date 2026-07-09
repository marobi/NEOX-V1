# 6502 Control and Debug

The RP side has direct hardware/debug authority over the 6502.

## Control states

The RP state machine can place the 6502 system into states such as:

```text
BOOT
RESET
HALTED
RUNNING
READ
RPI
```

These states control reset, RDY, BE, PHI2, bus direction, and control ownership.

## Capabilities

- reset
- run
- halt
- single-cycle execution
- single-instruction stepping
- memory read/write
- MMU page map inspection/modification
- context switch interaction
- IRQ generation
- monitor-entry IRQ
- disassembly

## Boundary

RP-side 6502 control signals are physical/debug control. They are not NEOX software signals.

MicMon is one front-end to these capabilities.
