# On-screen and Transparent Line Editing

The RP side owns the screen and implements transparent line editing for screen-mode console input.

## Ownership

```text
RP VDU
  owns framebuffer
  owns text buffer
  owns visual cursor rendering
  owns screen-line editing behavior

neosh
  prints prompts
  reads completed lines from stdin
  strips prompt prefix when needed
  dispatches the resulting command line
```

The shell does not own character-by-character screen editing. It consumes the completed edited line supplied by the RP console path.

## Transparent line editing model

In as-screen mode:

1. Keyboard input is rendered into the RP VDU screen line.
2. Control characters can move the cursor, delete characters, insert characters, clear to end of line, and switch insert/overwrite behavior.
3. On Enter, the RP reads the current screen line from the VDU text buffer.
4. The RP restores/advances the cursor as needed.
5. The RP pushes the edited line plus carriage return to the 6502 input queue.
6. The 6502 process reads the completed line through normal console input.

## Current edit controls

Current VDU control operations include:

```text
^A  cursor begin-of-line
^B  cursor left
^D  delete at cursor
^E  cursor end-of-line
^F  cursor right
^I  insert mode
^K  clear to end of line
^L  clear screen
^N  cursor down
^O  overwrite mode
^P  cursor up
^T  instant scroll
^U  smooth scroll
```

Backspace moves the cursor left. Printable characters update the current screen cell; in insert mode, the line is shifted before insertion.

## Mouse interaction

A text-mode left click moves the RP VDU text cursor. That affects where subsequent screen editing happens. It does not automatically imply a NEOX process focus change.
