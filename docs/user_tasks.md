# NEOX User Tasks

The static user image contains six boot-task entries. Tasks 1–5 are diagnostics
or regression tests. Task 6 is the interactive shell bootstrap.

The task entry table is defined in:

```text
user/task/user_entry.asm
```

The task sources are owned by:

```text
user/task/
```

## Static task image

`user/task/user_image.asm` aggregates the task entry table and the six task
modules into the resident user image.

Each task executes in its own process context and uses the normal NEOX syscall
interface. User tasks must not use BIOS/simple I/O. Input and output pass
through inherited descriptors and NEOX syscalls.

## Task 1 — pipe ping/pong initiator

Source and entry:

```text
user/task/task1.asm
user_task1_entry
```

Task 1:

- validates inter-process pipe operation with Task 2;
- writes `P` to fd 3;
- reads the response from fd 4;
- counts completed request/response loops;
- samples `sys_ticks`;
- reports the measured loop rate through stdout.

Descriptor mapping:

```text
fd 3  Task 1 -> Task 2
fd 4  Task 2 -> Task 1
```

## Task 2 — pipe ping/pong responder

Source and entry:

```text
user/task/task2.asm
user_task2_entry
```

Task 2:

- blocks reading one byte from fd 3;
- verifies that the byte is `P`;
- writes `Q` to fd 4;
- reports specific diagnostic markers for read, write, transfer-count, or
  content failures.

Tasks 1 and 2 form one diagnostic pair.

## Task 3 — console echo diagnostic

Source and entry:

```text
user/task/task3.asm
user_task3_entry
```

Task 3:

- reads one byte from stdin;
- writes that byte to stdout;
- exits when the byte is uppercase `Q`;
- exits on a syscall error or short transfer.

It uses only the normal descriptor-based console path.

## Task 4 — filesystem read smoke test

Source and entry:

```text
user/task/task4.asm
user_task4_entry
```

Task 4:

- opens `TEST.TXT`;
- reads up to 64 bytes;
- writes the received bytes to stdout;
- closes the file;
- reports short failure markers;
- exits after one pass.

It is a narrow read-only smoke test, not a general file utility.

## Task 5 — filesystem regression suite

Source and entries:

```text
user/task/task5.asm
user_task5_entry
user_task5_disabled_entry
```

The static task table currently selects:

```text
user_task5_disabled_entry
```

The full regression suite remains present in the image but is not executed as
an active boot task.

Its full entry exercises:

- save/load memory and file operations;
- open modes;
- seek and tell;
- delete and rename;
- directory open/read/close;
- mkdir and rmdir;
- per-process current working directory;
- relative and absolute path handling.

Task 5 creates, modifies, verifies, and removes test files and directories. It
must only be enabled deliberately.

## Task 6 — interactive shell bootstrap

Source and entry:

```text
user/task/task6.asm
user_task6_entry
```

Task 6 is intentionally small. It:

1. initializes the process-private cc65 runtime;
2. clears C BSS and initializes the software stack through
   `neox_cc65_runtime_init`;
3. transfers control to `neosh_main`.

Task 6 does not own prompt generation, line input, command parsing,
redirection, command lookup, or applet implementation.

Normal control flow:

```text
user_task6_entry
    -> neox_cc65_runtime_init
    -> neosh_main
    -> nbox command resolution
    -> parent applet or resident child applet
```

## Ownership boundaries

```text
user/task
  task entry table
  diagnostic tasks
  task 6 shell bootstrap

user/shell
  interactive shell policy and execution orchestration

user/nbox
  resident command resolution and dispatch

user/applets
  command implementations

libneox
  public user API and cc65 integration

kernel
  process contexts, scheduling, descriptors, pipes, spawn, wait and syscalls
```

## Validation implications

When validating the task layer, confirm:

- the static table still contains six task entries;
- Tasks 1 and 2 retain complementary pipe descriptors;
- Task 3 uses stdin/stdout only;
- Task 4 exits after one filesystem pass;
- Task 5 remains disabled unless explicitly enabled;
- Task 6 initializes cc65 before entering `neosh`;
- no task uses BIOS/simple I/O.
