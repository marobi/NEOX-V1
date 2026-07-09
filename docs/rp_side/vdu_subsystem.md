# VDU Subsystem

The RP side owns the VDU screen.

## Responsibilities

- framebuffer/text rendering
- screen text buffer
- cursor rendering
- cursor blink task
- smooth scrolling
- VDU control characters
- transparent screen-line editing
- mouse pointer overlay coordination

## Text buffer

The RP VDU maintains a text buffer representing screen cells. This allows the RP to support screen-based editing and to extract the current edited line when the user presses Enter.

## Cursor ownership

The cursor blink task remains the owner of cursor blink state. Other VDU operations may temporarily hide/redraw the cursor but must not become independent cursor blink owners.

## Screen modes

Some modes are “as-screen” modes. In those modes, printable characters and edit/control operations affect the RP-side screen line. On Enter, the RP can return the current screen line to the 6502 input queue.
