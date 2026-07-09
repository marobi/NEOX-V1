# USB Subsystem

The RP side acts as USB host.

## Supported device classes

- USB keyboard
- USB mouse
- USB MSC storage

The practical working configuration assumes a powered USB hub when keyboard, mouse, and storage are used together.

## Storage

USB MSC storage is mounted through the RP-side storage/FatFs layer. NEOX filesystem syscalls reach storage through the mailbox and RP filesystem backend.

## HID activation

Keyboard and mouse handling use staged activation so storage and HID startup remain stable when multiple devices are present.

## Diagnostics

Serial1 output is diagnostic only. Standalone operation must not depend on Serial1.
