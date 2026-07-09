# 6502 Clock and IRQ Generation

The RP side generates the 6502 PHI2 clock and also generates IRQ requests for timer and monitor entry.

## PHI2 clock generation

The RP configures a PWM output on the 6502 PHI2 pin. The clock frequency is controlled by the RP-side clock setting.

Monitor command:

```text
clock <freq MHz>
```

Without a useful non-zero argument, the command reports the currently configured frequency. With a frequency, it sets the requested 6502 clock frequency and reports it.

## Clock stop and manual stepping

The RP can stop PWM clock generation and force PHI2 high. Manual stepping uses direct GPIO toggles of PHI2.

Capabilities:

```text
single-cycle
single-step instruction
halt in/read cycle support
```

Monitor commands:

```text
sc <cycles>   single-cycle clock stepping
ss <steps>    single-instruction stepping using SYNC observation
```

## IRQ generation

The RP can generate IRQs for the 6502 by updating shared IRQ state/source and asserting the IRQ line.

IRQ sources currently include:

```text
RP_SRC_TIMER
RP_SRC_MONITOR
```

Monitor command:

```text
irq           generate timer-source IRQ once
mon/itor      request monitor entry through monitor-source IRQ
```

## IRQ timer

The RP can generate periodic timer IRQs.

Monitor command:

```text
timer <freq>
```

The command converts frequency to a millisecond interval and starts or stops the IRQ timer. A non-positive or invalid interval stops the timer.

## Acknowledge model

The RP tracks whether an IRQ is pending. It expects the 6502 side to acknowledge by clearing the shared IRQ source/state. If another IRQ is requested while one is still pending, the RP refuses the new IRQ and records/report errors.

## Safety

IRQ generation is RP hardware/service control. It must not directly call filesystem/mailbox service code from IRQ context.
