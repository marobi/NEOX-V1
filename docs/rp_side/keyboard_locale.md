# Keyboard Locale

The RP USB keyboard layer owns HID keycode to character translation before input is routed to the 6502 console queue.

## Built-in layouts

Current built-in layouts:

```text
US
DE
```

The active layout is table-driven. A later storage-backed layout loader can install a custom table without changing the HID input pipeline.

## Runtime monitor command

MicMon provides:

```text
keymap
keymap us
keymap de
```

Without an argument, `keymap` prints the current layout. With `us` or `de`, it changes the active layout.

## Default layout

The default layout is configured on the RP side by `USB_KEYBOARD_DEFAULT_LOCALE`.

## Current character scope

The current mappings are ASCII-oriented. Extended German characters such as `ä`, `ö`, `ü`, `ß`, `€`, `§`, and dead-key behavior are intentionally not exposed until NEOX has a defined extended keyboard/character encoding.

## DK61SE note

For the DIERYA DK61SE-specific ESC/top-left-key behavior:

- plain ESC remains ESC
- keyboard firmware can emit the backtick keycode through Fn+ESC
- Fn+Shift+ESC may not be distinguishable from Fn+ESC
- Shift+ESC is reserved as a reliable way to type `~` for 8.3 aliases such as `LONGFI~1.TXT`

That behavior is keyboard-specific and should remain conditional or explicitly documented in the keyboard layout layer.
