# V29n cleanup

This cleanup keeps the working ABI v2 mailbox/IRQ layout and removes the defensive include guard that was temporarily added while `rp_console_io.asm` was being split out.

## Kept

- Mailbox ABI v2 at `$E000`
- IRQ/shared bytes at `$E010..$E013`
- Separate `kernel/rp2350.asm` transport module
- Separate `kernel/rp_console_io.asm` console mailbox-use module
- Makefile builds both modules as separate objects

## Removed

- `RP2350_TRANSPORT_ASM = 1` marker from `kernel/rp2350.asm`
- `.ifndef RP2350_TRANSPORT_ASM` guard around `kernel/rp_console_io.asm`

The source now fails normally if someone accidentally includes `rp_console_io.asm` from another assembly unit, which is preferable because the intended build model is explicit separate objects.
