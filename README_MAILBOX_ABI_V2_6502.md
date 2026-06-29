# NEOX 6502 mailbox ABI v2 conversion

This source set converts the NEOX 6502-side mailbox definitions and console I/O usage to the RP mailbox ABI v2 layout.

## ABI v2 block

The request block still starts at `RP_REQ_BASE = $E000`, but the first bytes are now:

```text
$E000 RP_GROUP
$E001 RP_CMD
$E002 RP_STATUS
$E003 RP_ERR
$E004 RP_FLAGS
$E005 RP_STATE
$E006 RP_ARG0L
$E007 RP_ARG0H
$E008 RP_ARG1L
$E009 RP_ARG1H
$E00A RP_ARG2L
$E00B RP_ARG2H
$E00C RP_RES0L
$E00D RP_RES0H
$E00E RP_RES1L
$E00F RP_RES1H
```

`RP_DOORBELL` is trigger-only and is written with `RP_DOORBELL_TRIGGER`.

## Source split

- `kernel/rp2350.asm` now contains low-level mailbox transport only.
- `kernel/rp_console_io.asm` contains console read/write mailbox command usage.

The old console command-byte doorbell writes were removed from the 6502 side.


## v29i build integration note

`kernel/rp_console_io.asm` remains the separate owner of console mailbox command usage.
For now it is included from `kernel/rp2350.asm` so the current kernel link list, which only links `rp2350.o`, resolves the exported console symbols without requiring a Makefile change.

Do not also add `rp_console_io.o` to the linker object list unless the `.include "rp_console_io.asm"` line is removed from `kernel/rp2350.asm`, otherwise the exported symbols will be defined twice.


## Build integration note

`kernel/rp2350.asm` and `kernel/rp_console_io.asm` are separate translation units.

`rp2350.asm` owns the low-level RP mailbox transport helpers.
`rp_console_io.asm` owns the console mailbox command usage and imports the transport helpers.

The kernel build must assemble and link both objects exactly once:

```text
out/kernel/rp2350.o
out/kernel/rp_console_io.o
```

Do not include `rp_console_io.asm` from `rp2350.asm` when the Makefile already builds `rp_console_io.o`, because that defines the imported transport symbols twice during assembly.


## V29k build guard

`kernel/rp2350.asm` and `kernel/rp_console_io.asm` are separate translation units. The Makefile assembles and links both objects explicitly; `rp2350.asm` must not include `rp_console_io.asm`.
