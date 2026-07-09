# Validation Notes

This document records validated behavior categories, not generated ZIP names or software version numbers. Specific build identifiers belong in release notes.

## Validated shell behavior categories

- `HELP`
- `PWD`
- `CD`
- `LS`
- `CAT`
- `CP`
- `PS`
- child-mode applet execution through `nbox_child_entry`
- parent/direct execution for `CD`
- cwd inheritance for spawned children
- fd 0/1/2 inheritance for spawned children
- waitpid/zombie/reap lifecycle
- compact help after removing spawn diagnostic applets

## Validated RP behavior categories

- USB keyboard, mouse, and MSC through powered hub
- keyboard locale command exists for US/DE selection
- RP-side VDU text-mode mouse overlay
- pointer hidden during smoothscroll/redraw
- cursor blink task remains cursor blink owner
- left-click moves VDU cursor in text mode
- RP monitor can inspect/control CPU, memory, clock, IRQ, MMU, and storage diagnostics

## Known design constraints

- `CAT` must remain byte-exact.
- Shell redirection is not yet part of the documented validated command behavior.
- Pipes are kernel objects and future shell pipe setup must happen in `neosh` before child commit.
- Mailbox is a central service ABI, not a filesystem-only interface.
