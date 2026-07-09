# Console Focus Selection

The RP side controls where keyboard input is routed.

## Concepts

```text
console owner
  target PID/context for console input/output routing

active context
  MMU context selected for 6502 execution or monitor inspection

active_pid
  6502 kernel's authoritative running process id
```

These are related but not identical.

## Input focus

Function keys can be used for keyboard-only context/console selection. Focus changes may print Serial1 diagnostics, but Serial1 must not be required for standalone operation.

## Path

```text
USB keyboard
  -> RP input router
  -> console/context focus selection
  -> selected 6502 input queue
```

## Future mouse focus

Mouse click focus selection can be added later, but policy must be explicit. Moving the VDU cursor and changing console focus are different actions.
