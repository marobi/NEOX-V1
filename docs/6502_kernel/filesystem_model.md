# Filesystem Model

The RP side owns storage and filesystem backends. The 6502 side owns NEOX-visible filesystem semantics.

## Ownership split

```text
RP side
  USB MSC
  FatFs
  storage mount/unmount
  file/directory backend operations

6502 kernel
  fd table
  open object table
  cwd per process
  path resolution policy
  syscall ABI
  shell-visible behavior
```

## CWD

The current directory is process-private on the 6502 side. The RP side does not own a global current directory.

The RP side receives explicit resolved device/path data from the 6502 kernel or from monitor commands.

## File access path

Normal user file access goes through:

```text
user/app
  -> NEOX syscall
  -> 6502 kernel fd/open-object layer
  -> RP mailbox request
  -> RP filesystem backend
```

Monitor commands may also call RP filesystem functions directly for diagnostics. Those monitor commands are not NEOX syscalls.

## CAT rule

`CAT` is byte-exact. It must not append CR/LF or otherwise alter file contents while writing to stdout.

## PC/USB sharing rule

USB/PC sharing is allowed only while the 6502 is reset or inactive. When the 6502 is running, storage ownership must be unambiguous.
