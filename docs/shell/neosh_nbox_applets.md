# neosh, nbox, and Applets

## neosh

`neosh` is the interactive shell task. It owns shell policy:

- prompt generation
- receiving complete edited command lines
- prompt-prefix stripping
- command resolution
- parent/direct versus child/spawned execution policy
- redirection setup and future pipe setup
- child spawn/commit/wait orchestration

The RP VDU/console layer owns the screen and transparent line editing. `neosh` consumes the completed edited line delivered through stdin.

## nbox

`nbox` is the resident applet dispatcher/executor. It handles one command line or one applet launch. It must not own:

- prompts
- process allocation
- fd setup policy
- redirection
- pipes
- shell job policy

## Applets

Applets are individual command implementations. Command wrappers parse command-line arguments for direct dispatch. Spawned child applets use `nbox_child_entry`, which loads launch arguments first and then calls core applet routines directly.

## Shared applet scratch

Applet scratch storage is shared inside the resident user image. This is acceptable because one applet runs inside one process/context at a time. Kernel state must not rely on that assumption.

## CAT stdin mode

`cat` with a pathname opens and copies that file. With no pathname it
copies inherited fd 0 to fd 1 until EOF:

```text
cat FILE.TXT
cat < FILE.TXT
```

This also provides the required filter behavior for later pipelines.

## ECHO

`echo` is a resident child-mode applet used to exercise spawn and stdout
redirection:

```text
echo
echo HELLO
echo HELLO WORLD
echo TEST > TMP.OUT
echo MORE >> TMP.OUT
```

The current command ABI supplies at most two arguments. `echo` joins
them with one space and always writes a trailing CR. It does not yet
implement quoting, escapes, variables, or `-n`.


## KILL

`kill` is a parent-mode applet. It accepts only numeric Linux-compatible signal
numbers:

```text
kill -2 PID
kill -9 PID
kill -18 PID
kill -19 PID
```

The applet produces no output when the signal is accepted. It reports usage,
invalid signal, invalid PID, or syscall failure through inherited stderr.


The `ps` `SIG` column displays pending Linux-compatible signal numbers in
decimal. Single-digit values are right-aligned:

```text
 0
 2
 9
18
19
```


The `ps` display no longer includes the transient `HOLD` gate-ownership column.
Gate ownership remains available through kernel and RP-side diagnostics.
