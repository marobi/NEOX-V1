# libneox and the cc65 userland target

## Purpose

`libneox` exposes compiler-neutral NEOX interfaces to user applications while
keeping compiler-specific calling conventions inside backend modules.

The initial backend targets cc65. Kernel, BIOS, syscall cartridge, and MICMON
remain ca65/ld65 components.

## Process-private C memory

```text
$0020-$007F  cc65/libneox zero-page state
$1000-$7BFF  resident user image, C data, and C BSS
$7C00-$7FFF  1 KiB cc65 software stack
```

Kernel syscall zero page remains outside the cc65 allocation.

## Startup

Task 6 calls `neox_cc65_runtime_init` before entering `neosh`. Runtime
initialization:

1. initializes `c_sp` to the top of the reserved software stack;
2. clears the complete `C_BSS` segment;
3. returns to the assembly shell wrapper.

No cc65 crt0, constructors, destructors, heap, libc stdio, or standard startup
sequence is used.

## Build chain

```text
cc65 -t none --cpu 65c02
    -> generated assembly

ca65
    -> C objects and NEOX backend objects

ld65 -C libneox/cc65/cfg/neox.cfg
    -> NEOX user image
    -> installed none.lib supplies compiler helpers on demand
```

The final image is linked directly with `ld65`; `cl65` does not control startup
or cartridge composition.

## Segment ordering

All file-backed segments must occur before `C_BSS` and `BSS`. BSS occupies
runtime memory but contributes no bytes to the raw image. This invariant keeps
physical load offsets identical to linked run addresses.

## Public write interface

```c
neox_status_t neox_write(
    neox_fd_t fd,
    const void* buffer,
    neox_size_t requested,
    neox_size_t* written_out);
```

The public declaration uses ordinary C arguments. The cc65 backend converts
those arguments to the fixed NEOX `rw_args` syscall block and invokes
`SYS_WRITE`. Userland does not use BIOS/simple I/O.
