# Validation Notes

This document records validated behavior categories, not generated ZIP names
or software version numbers. Specific build identifiers belong in release
notes.

## Validated shell behavior categories

- - `PWD`
- `CD`
- `LS`
- `CAT`
- `ECHO`
- `RM`
- `MV`
- `MKDIR`
- `RMDIR`
- `CP`
- `PS`
- child-mode applet execution through `nbox_child_entry`
- parent/direct execution for `CD`
- cwd inheritance for spawned children
- fd 0/1/2 inheritance for spawned children
- waitpid/zombie/reap lifecycle
- stdout redirection with create/truncate semantics for `>`
- stdout redirection with preserve/seek-to-end semantics for `>>`
- `cat` stdin mode for redirected descriptor 0

## Validated cc65/libneox behavior categories

- process-private cc65 zero-page allocation
- cc65 software-stack initialization
- C BSS clearing before C execution
- assembly-to-C and C-to-assembly call/return
- ordinary cc65 fixed-argument calls with callee stack cleanup
- standard compiler-runtime helpers resolved from `none.lib`
- public `neox_write(fd, buffer, requested, written_out)` through descriptor 1
- return from `SYS_WRITE` through compiled C to the assembly shell
- file-backed linker segments placed before `C_BSS` and `BSS`

## Validated RP behavior categories

- USB keyboard, mouse, and MSC through powered hub
- keyboard locale command exists for US/DE selection
- RP-side VDU text-mode mouse overlay
- pointer hidden during smoothscroll/redraw
- cursor blink task remains cursor blink owner
- left-click moves the VDU cursor in text mode
- RP monitor can inspect/control CPU, memory, clock, IRQ, MMU, and storage diagnostics

## Known design constraints

- `CAT` must remain byte-exact.
- Pipes are kernel objects; shell pipe setup must happen in `neosh` before
  child commit.
- Mailbox is a central service ABI, not a filesystem-only interface.
- `libneox` does not use BIOS/simple I/O.
- The initial cc65 runtime has no crt0, heap, constructors, destructors, or
  standard-library I/O.
