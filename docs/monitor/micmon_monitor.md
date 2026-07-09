# RP-side MicMon / Control Monitor

This document describes the RP-side MicMon/control monitor. It is an out-of-band machine/debug monitor, not a NEOX shell and not a NEOX user process.

There is also a separate 6502 MicMon monitor that runs as 6502 code. See `6502_micmon_monitor.md`.

## What MicMon is not

The RP-side monitor is not:

- `neosh`
- `nbox`
- a NEOX user process
- normal process signalling
- normal application-level console input

## Command capabilities

The current monitor command set includes the following groups.

### CPU/run control

```text
r/eset        reset 6502 and mailbox/cmd state
s/top         halt CPU
g/o           run CPU
st/at         print CPU/bus/control/RW/clock status
```

### Clock and stepping

```text
clock <MHz>   set/report 6502 PHI2 clock frequency
sc <cycles>   single-cycle the 6502 clock
ss <steps>    single-step instructions and disassemble current instruction position
```

### IRQ and monitor entry

```text
irq           generate one timer-source IRQ
mon/itor      request monitor entry through monitor-source IRQ
timer <freq>  start/stop periodic RP-generated timer IRQs
```

### Memory and disassembly

```text
m/em <from> <to>       dump memory
d/is <from> <lines>    disassemble memory
> <addr> <data...>     modify memory bytes and dump written range
zero                   zero memory
```

The `>` monitor command is memory modification, not shell redirection.

### MMU/context

```text
ctx                   show current MMU context and page map
page <index> <page>   change one MMU page mapping for current context
```

### Console/session focus

```text
t/erm [PID]            enter terminal/console mode for selected PID
```

PID 0 is monitor/ICM. Non-zero PID routes terminal input to the selected console PID if monitor state allows it.

### Keyboard locale

```text
keymap                 show active USB keyboard layout
keymap us              select US layout
keymap de              select German layout
```

### USB/storage diagnostics

```text
usbdisks              print USB MSC/FatFs slot state
fstest [device]       RP-local TEST.TXT/BIG.TXT read test
ls [dev] [path]       list directory using RP filesystem API
fsbulk [dev] [ctx]    bulk save/load diagnostic test
```

`fstest` and `fsbulk` are diagnostic/test commands. They are not normal NEOX filesystem syscalls.

### NEOX diagnostics

```text
ps                    dump NEOX scheduler/process diagnostic info
syscfg                enter system configuration menu
help                  print MicMon help
```

## Safety boundaries

- MicMon memory reads may be live snapshots.
- MicMon memory writes are invasive.
- MicMon filesystem diagnostics may call RP filesystem functions directly and therefore bypass normal NEOX syscall semantics.
- MicMon hardware control is out-of-band relative to NEOX processes.


## Relationship to the 6502 MicMon monitor

The RP-side monitor and the 6502 MicMon monitor serve different layers.

```text
RP-side MicMon/control monitor:
  controls the machine externally
  owns run/halt/reset/clock/IRQ control
  can perform transparent memory inspection
  provides RP-side diagnostics and hardware/backend commands

6502 MicMon monitor:
  runs on the 6502
  captures 6502 register state through BRK/warm entry
  provides 6502-side memory/register/disassembly/assembly commands
```

Architectural documentation should qualify the name when the distinction matters.
