# libneox cc65 backend

This directory contains the NEOX-specific cc65 integration layer.

## Components

- `zeropage.asm` defines the process-private cc65 zero-page symbols in
  `$0020-$007F`.
- `runtime.asm` initializes the cc65 software stack at `$7C00-$7FFF` and
  clears `C_BSS`.
- `neox_write.asm` implements the compiler-neutral public `neox_write()`
  interface at the ordinary cc65 argument ABI boundary.
- `cfg/neox.cfg` maps assembly, C, runtime, zero-page, BSS, and software-stack
  segments into the NEOX process address space.

## Toolchain and link model

C files are compiled with `cc65 -t none --cpu 65c02`. Generated assembly and
NEOX backend modules are assembled with `ca65`. The final user image is linked
directly with `ld65` and the project-owned `cfg/neox.cfg`.

Compiler-generated helper routines are resolved from the installed standard
cc65 `none.lib` archive. `none.lib` is passed only to the `ld65` command; it is
not a project-local Make prerequisite. Archive extraction includes only the
members required by unresolved compiler-runtime symbols.

The NEOX build does not use the standard cc65 startup module or standard I/O.
NEOX owns process startup, BSS initialization, descriptor I/O, syscalls, and
cartridge layout.

## Mandatory segment-order invariant

Every file-backed segment must precede `C_BSS` and `BSS` in `cfg/neox.cfg`.
Raw binaries omit BSS bytes. Placing file-backed code after BSS would make the
loaded byte positions differ from their linked run addresses.

## Toolchain baseline

- cc65 V2.19, Git cc3c40c
- ca65 V2.19, Git cc3c40c
- ld65 V2.19, Git cc3c40c


## Process and positioning wrappers

The backend also provides public C boundaries for:

```text
neox_seek
neox_spawn_resident
neox_waitpid
neox_signal
neox_get_launch_id
neox_get_launch_line
```

Shell code uses these APIs rather than private shell-specific syscall blocks.
