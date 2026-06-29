# NEOX IRQ shared-state ABI v2 fix

This version fixes the IRQ acknowledgement address mismatch introduced by the mailbox ABI v2 request-block move.

RP V29g uses:

```text
RP_IRQ_SOURCE = $E010
RP_CONSOLE_PID = $E011
RP_CONSOLE_RDY = $E012
RP_IRQ_STATE = $E013
```

The previous 6502 BIOS definitions still used the old locations:

```text
BIOS_IRQ_SOURCE = $E00C
BIOS_IRQ_STATE = $E00F
```

Those old locations now overlap ABI v2 result fields `RP_RES0L` and `RP_RES1H`. Therefore `BIOS_ACK_IRQ` cleared the wrong byte and waited on the wrong byte. Timer IRQ acknowledgement did not reach the RP side.

Changed files:

```text
bios/bios.inc
include/mailbox.inc
kernel/main.asm
```

Current shared-state layout:

```text
$E000..$E00F  ABI v2 mailbox request/result block
$E010         RP_IRQ_SOURCE / BIOS_IRQ_SOURCE
$E011         RP_CONSOLE_PID
$E012         RP_CONSOLE_RDY
$E013         RP_IRQ_STATE / BIOS_IRQ_STATE
```

`kernel/main.asm` now clears `$E000..$E013` during RP init.
