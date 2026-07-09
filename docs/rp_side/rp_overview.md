# RP-side Overview

The RP side is not a passive peripheral. It owns the hardware-facing part of the system and has out-of-band authority over the 6502 machine.

## RP roles

1. **Device/backend host**
   - USB host
   - USB keyboard and mouse
   - USB MSC storage
   - FatFs
   - VDU display

2. **Service bridge**
   - mailbox dispatcher
   - console service
   - filesystem service
   - input queues

3. **Screen and input owner**
   - VDU framebuffer/text buffer
   - cursor rendering
   - transparent line editing
   - keyboard locale translation
   - VDU mouse overlay
   - context/console focus routing

4. **6502 control/debug authority**
   - PHI2 clock generation
   - reset/run/halt
   - single-cycle and single-step
   - IRQ generation and IRQ timer
   - debugger and disassembler support

5. **Transparent memory authority**
   - direct memory inspection
   - halted memory writes
   - passive live reads
   - invasive live debug writes when explicitly requested

## Boundary

The RP side provides hardware/backend/control services. The 6502 side owns NEOX process, fd, cwd, shell, pipe, and syscall-visible semantics.
