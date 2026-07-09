# Pipes

Pipes are kernel objects, not shell/app objects.

## Model

A pipe provides two fd-facing endpoints:

```text
read end
write end
```

Applets should use normal fd I/O. They must not know whether fd 0/1/2 is console, file, or pipe.

## Blocking behavior

Pipe read may block when no data is available and at least one writer exists. Pipe write may block when the pipe buffer is full and at least one reader exists.

The implementation must use wait/wakeup, not indefinite spinning.

## EOF and broken pipe

A pipe read reaches EOF when no data remains and no writer remains. A pipe write with no reader should fail with a broken-pipe style error.

## Shell setup

For future shell pipe support:

```text
cmd1 | cmd2

neosh:
  create pipe
  spawn cmd1 with fd 1 = pipe write end
  spawn cmd2 with fd 0 = pipe read end
  close parent pipe copies as needed
  wait/reap children
```

The pipe setup belongs to `neosh`, not `nbox`.
