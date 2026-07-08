# NEO6502_MMU / NEOX Current Development State

## Current accepted NEOX baseline

Current accepted NEOX source baseline:

`NEOX_V1_v38h1g1_spawnc_command_len_65.zip`

NEOX version:

`0.98.65`

This is the current working baseline for continuing the spawn/process work.

## Validated features in the current baseline

### nbox structure

`nbox` has been split into separate applet source files.

Current direction:

- `user/nbox.asm` remains the dispatcher/shared support module.
- Applets live in `user/applets/*.asm`.
- Applet file names use command names, for example:
  - `ls.asm`
  - `cat.asm`
  - `cp.asm`
  - `ps.asm`
  - `spawn.asm`
- Public applet entry symbols remain prefixed to avoid ca65 global symbol collisions.
- `nbox` remains the one-command resident applet executor.
- `nbox` must not own prompts, redirection, pipes, process allocation, or fd setup policy.

### Shell/process split

Current agreed architecture:

- Parent process owns spawn setup.
- `neosh` is the first important parent process that will use this, but the spawn ABI is not `neosh`-specific.
- `neosh` owns shell behavior:
  - prompt
  - readline
  - command parsing
  - redirection syntax
  - pipe syntax
  - command/appet selection
  - later wait orchestration
- Kernel owns:
  - process allocation
  - context allocation
  - fd tables
  - fd cloning/closing/duplication
  - spawn setup mechanics
  - process state transitions
  - later wait/zombie lifecycle
- `nbox` only executes the selected resident applet.

## Context model

Kernel-owned context state is now present.

Defined context states:

```asm
CTX_INVALID          = $00
CTX_RESERVED         = $01
CTX_PRELOADED_FREE   = $02
CTX_EMPTY_FREE       = $03
CTX_IN_USE           = $04
```

Current RP preload model:

- Context `0` is reserved for BIOS/kernel/monitor/supervisor usage.
- Contexts `1..9` are preloaded with `neox_user.rom`.
- A preloaded context is not automatically free; it is free only when the kernel context table marks it `CTX_PRELOADED_FREE`.

Current rules:

- Resident spawn may allocate only `CTX_PRELOADED_FREE`.
- Later dynamic executable loading may allocate `CTX_PRELOADED_FREE` or `CTX_EMPTY_FREE`.
- If an external executable overwrites a preloaded user image, that context must not return to `CTX_PRELOADED_FREE` unless the resident image is restored.
- Empty process slots use `proc_context = $FF`.
- Context `0` must never be used as a “no context” sentinel.

## Process/context allocation

Static boot task setup no longer accepts context numbers from `user_entry.asm`.

Old model, now obsolete:

```asm
.byte context
.byte reserved
.word entry
```

Current model:

```asm
.byte flags
.byte reserved
.word entry
```

The user task table supplies entry points. The kernel allocates the PID and a preloaded context.

Validated behavior:

- Static boot task creation still results in the expected mapping:
  - PID 1 owns CTX 1
  - PID 2 owns CTX 2
  - PID 3 owns CTX 3
  - PID 6 owns CTX 6
- Empty PID slots have context `$FF`.
- Free preloaded contexts return to `PRF` in the RP monitor.

## Current validated process/context monitor state

After the `SPAWNC` diagnostic child ran and exited, the expected stable state was observed:

```text
PPID PID State Sig SP Ctx Flg Mem  | Wait Obj | FD:
 255   0 RDY/RUN - FF 000 01 0000 |   -   -- | 0:r  1:w  2:w
   0   1 RUN/BLK - F9 001 00 2136 | ...      | ...
   0   2 RDY/BLK - F9 002 00 21FA | ...      | ...
   0   3 BLK     - F5 003 00 224E | CON  00 | 0:r  1:w  2:w
 255   4 EMP     - .. 255 00 0000 |   -   -- | -
 255   5 EMP     - .. 255 00 0000 |   -   -- | -
   0   6 BLK     - F5 006 00 2DFF | CON  00 | 0:r* 1:w  2:w
 255   7 EMP     - 00 255 00 0000 |   -   -- | -

Context State Owner
  0     RSV   FF
  1     USE   01
  2     USE   02
  3     USE   03
  4     PRF   FF
  5     PRF   FF
  6     USE   06
  7     PRF   FF
  8     PRF   FF
  9     PRF   FF
```

Important validated cleanup result:

- PID 4 returned to `EMP`.
- PID 4 context returned to `$FF`.
- CTX 4 returned to `PRF`.
- CTX 4 owner returned to `$FF`.

## Spawn setup ABI

Current accepted design is parent-controlled spawn setup.

The parent process performs:

```text
spawn_alloc_resident
configure child fd table
configure child execution descriptor later
spawn_commit
waitpid later
```

Current syscall set:

```asm
SYS_SPAWN_ALLOC_RESIDENT = $1B
SYS_SPAWN_FD_INHERIT    = $1C
SYS_SPAWN_FD_DUP_CHILD  = $1D
SYS_SPAWN_FD_CLOSE      = $1E
SYS_SPAWN_COMMIT        = $1F
SYS_SPAWN_ABORT         = $20
```

Current process state addition:

```asm
PROC_SETUP = $07
```

Rules:

- `SYS_SPAWN_ALLOC_RESIDENT` allocates a PID and `CTX_PRELOADED_FREE` context.
- The child is created as `PROC_SETUP`.
- `PROC_SETUP` children are not runnable.
- Only the creating parent may configure, commit, or abort the pending child.
- Kernel validation rule:

```text
proc_state[child] == PROC_SETUP
proc_ppid[child]  == active_pid
```

- `SYS_SPAWN_COMMIT` changes the child from `PROC_SETUP` to `PROC_NEW`.
- The scheduler may run the child only after commit.
- `SYS_SPAWN_ABORT` destroys a pending setup child and releases its context.

## Validated diagnostics

### `SPAWN`

Command:

```text
SPAWN
```

Validated behavior:

1. Allocates resident setup child.
2. Inherits fd `0`, `1`, and `2` into the child.
3. Leaves child paused in `PROC_SETUP`.
4. Monitor shows child state as `SET`.
5. Child context is marked `USE`.
6. Pressing Enter aborts the child.
7. Child process returns to `EMP`.
8. Context returns to `PRF`.

Validated during pause:

```text
PID 4:
  PPID  = 6
  State = SET
  Ctx   = 004
  FD 0  = inherited
  FD 1  = inherited
  FD 2  = inherited

CTX 4:
  State = USE
  Owner = 04
```

Validated after abort:

```text
PID 4:
  State = EMP
  Ctx   = 255
  FDs   = closed

CTX 4:
  State = PRF
  Owner = FF
```

### `SPAWNC`

Command:

```text
SPAWNC
```

Validated output:

```text
SPAWNC: ALLOC
SPAWN: CHILD PID $04
SPAWNC: COMMIT OK
SPAWNC CHILD RUN
```

Functional result:

- Allocated child PID 4.
- Inherited fd `0`, `1`, and `2`.
- Committed the child.
- Scheduler started the child.
- Child wrote to stdout.
- Child exited through `SYS_EXIT`.
- PID/context cleanup completed correctly.

Minor cleanup still needed:

```text
SPAWN: CHILD PID $04
```

inside `SPAWNC` should be changed to:

```text
SPAWNC: CHILD PID $04
```

This is cosmetic only.

## Discarded design branch

Discard the V38h1d ordered fd-action-table design.

Do not continue with:

- stored fd action table
- `spawn_apply_fd_actions`
- one-shot kernel action-list application

Accepted design instead:

- parent process calls spawn setup ABI step by step;
- kernel performs each fd setup operation immediately on the pending child;
- child remains `PROC_SETUP` until parent calls `SYS_SPAWN_COMMIT`;
- only the creating parent may configure, commit, abort, or later wait for the child.

## FD setup model

The child fd table is configured directly by kernel syscalls.

Normal command setup:

```text
child fd 0 <- parent fd 0
child fd 1 <- parent fd 1
child fd 2 <- parent fd 2
```

Later output redirection:

```text
child fd 0 <- parent fd 0
child fd 1 <- open OUT.TXT directly for child
child fd 2 <- parent fd 2
```

Later pipe producer:

```text
child fd 0 <- parent fd 0
child fd 1 <- parent pipe write fd
child fd 2 <- parent fd 2
```

Later pipe consumer:

```text
child fd 0 <- parent pipe read fd
child fd 1 <- parent fd 1
child fd 2 <- parent fd 2
```

Important rule:

- The parent process stdout must not be altered when setting up redirection.
- The fd setup belongs to the pending child execution environment.
- Redirection syntax is parsed by the parent/shell.
- The kernel performs fd mutations on the pending child.

## Version/build rule

Current NEOX version:

```asm
NEOX_VERSION_MAJOR = 0
NEOX_VERSION_MINOR = 98
NEOX_VERSION_BUILD = 65
```

Version string:

```text
0.98.65
```

Rule:

- Every generated NEOX source ZIP that changes source must increment `NEOX_VERSION_BUILD`.
- Next generated NEOX version should be `0.98.66`.

## Next planned milestone

Next version:

```text
V38h1h / 0.98.66
```

Goal:

```text
waitpid + zombie lifecycle
```

Required behavior:

- A committed child calling `SYS_EXIT` should become `PROC_ZOMBIE` if it has a real parent.
- Kernel stores child exit status.
- Add `SYS_WAITPID`.
- Parent may wait for a specific child PID.
- `waitpid` validates:

```text
proc_ppid[child] == active_pid
```

- If child is still running, parent blocks on `WAIT_PROC`.
- If child is zombie, parent receives exit status and reaps child.
- Add or extend a diagnostic command, likely `SPAWNW`, to test:
  - spawn
  - fd inheritance
  - commit
  - child exits with status
  - parent waits
  - child is reaped
  - context returns to `PRF`

## Do not implement yet

Do not implement these before wait/zombie is stable:

- real `nbox_child_entry`
- parsed applet descriptor
- argv descriptor/copying
- stdout redirection
- append redirection
- pipe syntax
- external executable loading
- C userland/libc/syscall layer

## C decision

Continue `neosh`/`nbox`/resident applets in assembler for now.

Reason:

- C requires a NEOX C userland ABI first:
  - `crt0`
  - syscall wrappers
  - minimal `libneox`
  - compiler/runtime validation
- The current work is still process/fd/context boundary work.
- Exact register/memory/fd behavior matters more than source-level convenience at this stage.

Later C is useful for larger external utilities, but not yet for the resident spawn/shell foundation.
