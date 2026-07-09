# VDU Mouse Support

Mouse support is currently RP-side text-mode VDU support.

## Current behavior

- RP draws a text-mode mouse pointer overlay.
- The pointer is filled rather than a crosshair.
- Mouse debug output is disabled in normal operation.
- The pointer is hidden during active smoothscroll/redraw operations.
- The cursor blink task remains the sole owner of cursor blink state.
- A left-button press edge in text mode moves the VDU text cursor to the mouse cell.

## Boundary

The mouse overlay is visual/input support on the RP side. It is not a 6502 process-management feature.

If mouse state or mouse events are exposed to NEOX later, that should be through an explicit input API.
