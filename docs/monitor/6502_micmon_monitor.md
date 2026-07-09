# 6502 MicMon Monitor

The 6502 MicMon monitor is a compact W65C02 machine monitor that runs on the 6502 side. It is separate from the RP-side MicMon/control monitor.

The 6502 monitor provides direct machine-level inspection and control from inside the 6502 execution environment. It is intended to fit in a small ROM area and to remain deterministic and self-contained.

## Distinction from the RP-side monitor

There are two monitor concepts in the system:

```text
RP-side MicMon/control monitor
  Runs on the RP side.
  Controls the 6502 machine from outside.
  Owns clock/run/halt/reset/IRQ/debug control.
  Can inspect memory transparently from outside the 6502 CPU path.

6502 MicMon monitor
  Runs as 6502 code.
  Uses BRK/warm monitor entry to capture and edit 6502 CPU state.
  Provides memory dump/edit, register edit, GO, disassembly and one-line assembly.
```

The 6502 monitor is not `neosh`, not `nbox`, and not a normal NEOX user command environment.

## Design goals

The uploaded MicMon source describes these goals:

```text
- small monitor footprint
- deterministic behaviour
- no dynamic allocation
- table-driven command dispatch
- table-driven disassembler/assembler support
- round-trip capable text output
- line-oriented command interface
```

The round-trip philosophy is important: monitor output is formatted so that it can be edited and fed back as monitor input where practical.

## Entry points

The source defines fixed monitor entry points at the start of the monitor ROM area:

```text
$B000  cold reset entry
$B003  warm kernel/supervisor monitor entry
```

The kernel should enter the monitor through the warm entry when it wants monitor access without doing a cold monitor reset.

## Cold reset entry

The cold reset path:

```text
- disables interrupts
- clears decimal mode
- initializes stack pointer
- initializes monitor memory pointer
- installs the BRK handler through the kernel entry table
- prints the welcome text
- enters the monitor using BRK
```

## Warm monitor entry

The warm monitor entry is for freeze-style monitor entry. It does not reset the stack, does not print the cold welcome text, and does not execute the cold reset sequence.

It installs the BRK vector and enters the monitor command loop.

## BRK entry and saved CPU image

The BRK entry saves the 6502 CPU image into monitor RAM:

```text
A
X
Y
status register
PC
SP
```

The BRK handler corrects the saved PC back to the BRK opcode address because BRK pushes PC+2.

The saved CPU image is then used by:

```text
R   register display
;   register edit
G   resume execution
```

## IRQ entry

The monitor source has a common IRQ/BRK entry path that distinguishes normal IRQ from BRK by testing the B flag in the stacked status byte.

For normal IRQ, the code returns through the IRQ restore path. For BRK, it enters the monitor state-save path.

The source also contains an IRQ context-switch path in the disassembly/listing. That path interacts with kernel/RP context-switch control and should be documented together with the kernel/RP IRQ and context-switch mechanism when that part is finalized.

## NMI entry

The NMI entry is currently a stub that returns with `RTI`.

## Command model

Commands are line-oriented and CR-terminated. Command dispatch is table-driven.

The command character table in the uploaded source is:

```text
H  help
M  memory dump
>  memory edit / poke bytes
R  show saved registers
;  edit saved registers
G  resume execution / GO
D  disassemble
A  assemble one instruction
Q  leave monitor
C  switch context
```

The command dispatcher uppercases the first command character before dispatch.

## Command summary

### `H` — help

Prints the compact command syntax overview.

### `M [start [end]]` — memory dump

Dumps memory from the current memory pointer or from an explicitly supplied address range.

If only a start address is supplied, the default dump length is 96 bytes.

The monitor updates its remembered memory pointer after the dump.

### `> addr byte...` — memory edit

Writes a byte stream to memory.

The current implementation writes one to eight bytes per command line and advances the remembered memory pointer to the byte after the last write.

This `>` command is monitor memory modification. It is not shell output redirection.

### `R` — register display

Displays the saved CPU image in an editable format.

The output starts with `;`, matching the register-edit command, so the register line can be edited and re-entered.

### `; PC [A [X [Y [SP [SR]]]]]` — register edit

Edits the saved CPU image.

At least the PC must be supplied. Missing trailing fields leave the corresponding saved registers unchanged.

### `G [addr]` — GO / resume execution

Restores the saved CPU image and resumes execution using `RTI`.

If an address is supplied, it replaces the saved PC before resuming.

### `D [addr]` — disassemble

Disassembles memory starting at the supplied address or the current remembered address.

The monitor includes W65C02 disassembler support.

### `A [addr] instruction` — assemble

Assembles a single instruction at the supplied address or at the current assembly address.

This is single-line immediate assembly. It does not provide labels, multi-line assembly, or an expression evaluator.

### `Q` — leave monitor

Prints `BYE` and returns through the kernel monitor-leave entry point.

### `C context` — switch context

Switches monitor-visible context using the parsed context parameter.

This is a monitor/context-control operation, not a shell command and not a normal process operation.

## Parameter formats

Numeric parameter parsing supports explicit prefixes:

```text
hexadecimal default: 0200
hexadecimal explicit: $0200
binary: %10101010
decimal: +123
ASCII byte: 'A
```

Hexadecimal is assumed when no prefix is present.

## Memory usage

The uploaded source uses a fixed zero-page workspace and a fixed BSS area:

```text
zero-page workspace: $00C0-$00DF region
line buffer:         $0200
saved CPU image:    after the line buffer in the same BSS area
```

The exact layout is implementation detail, but the important rule is that the 6502 monitor owns this workspace while it is active.

## Relationship to RP transparent editing

The 6502 MicMon assumes line-oriented input. The RP side may provide transparent line editing and screen ownership before a CR-terminated line is delivered to the monitor.

Therefore:

```text
RP side:
  owns physical screen rendering and transparent line editing

6502 MicMon:
  receives complete command lines
  executes monitor commands
  emits round-trip-compatible text where practical
```

This division is intentional. The 6502 monitor should not grow into a full-screen editor.

## Limitations

The current monitor design intentionally excludes:

```text
- multi-line assembly
- labels
- expression evaluation
- symbolic debugging
- process-aware shell behavior
```

It is a compact machine monitor, not a source-level debugger and not a shell.

## Documentation rule

When referring to MicMon, specify which monitor is meant:

```text
RP-side MicMon/control monitor
6502 MicMon monitor
```

Do not use the unqualified name `MicMon` in architectural documents where the distinction matters.
