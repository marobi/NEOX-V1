# NEOX build 128 memory layout

```text
$0000-$7FFF  private process space
$8000-$AFFF  shared NEOX core kernel (12 KiB target)
$B000-$B013  shared RP mailbox and IRQ/control bytes (ordinary RAM)
$B014-$B01F  reserved
$B020-$BFFF  shared kernel-state ABI
$C000-$CFFF  shared kernel overflow page (unused in build 128)
$D000-$DFFF  shared MICMON image
$E000-$EFFF  shared trap-write I/O page
$F000-$F0FF  shared BIOS services
$F100-$F1FF  separate shared syscall cartridge and veneers
$F200-$FFFF  BIOS-page reserve and hardware vectors
```

Mailbox request/result writes target ordinary shared RAM at `$B000`. Only the
doorbell write at `$E010` enters the trap-write I/O path and requests RP service.

The RP-visible shared-state ABI starts at `$B020` and is version `0x020A`.
