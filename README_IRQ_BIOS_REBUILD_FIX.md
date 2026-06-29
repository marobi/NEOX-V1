# IRQ BIOS ABI v2 fix

The source `bios/bios.inc` already used ABI v2 IRQ addresses, but the checked-in BIOS binary/listing still contained the old IRQ acknowledge addresses.

Fixed addresses:

```text
BIOS_IRQ_SOURCE = $E010
BIOS_IRQ_STATE  = $E013
```

Patched generated artifacts in this package:

```text
bios/bios.bin
bios/bios.rom
bios/bios.dis
bios/bios.LST
```

Also updated `bios/Makefile` so `bios.inc` and `../include/mailbox.inc` are dependencies of `bios.o`.

After installing this package, rebuild/install the BIOS or ensure the patched `bios/bios.rom` is copied to the RP-visible `data/system` location used at boot.
