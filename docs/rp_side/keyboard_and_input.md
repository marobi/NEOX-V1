# Keyboard and Input

The RP side receives USB HID input and routes it to the selected console/context.

## Input pipeline

```text
USB keyboard
  -> HID report decode
  -> keyboard locale mapping
  -> RP input router
  -> console/context focus selection
  -> VDU and/or 6502 input queue
```

## Functional path

Normal keyboard input must follow the functional path into the RP router and then to the selected console/context. Serial1 is diagnostic and monitor-facing only.

## Function keys

Function keys are keyboard-only context selection controls. They select where keyboard input is routed.

## Mouse events

Current mouse support is RP-side VDU support. If mouse events are later exposed to the 6502, they should go through an explicit input-event API.
