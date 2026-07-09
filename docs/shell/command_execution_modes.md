# Command Execution Modes

`nbox` exposes command resolution metadata used by `neosh`.

## Modes

```text
NBOX_EXEC_PARENT
  execute in shell process

NBOX_EXEC_CHILD
  execute in spawned child process

NBOX_EXEC_NONE
  no execution, empty line or no-op

NBOX_EXEC_UNKNOWN
  command not known
```

## Current policy

Parent/direct:

```text
CD
```

Child/spawned:

```text
HELP PWD LS CAT RM MV MKDIR RMDIR CP PS
```

## Why CD is parent/direct

`CD` changes the shell process cwd. Running it in a child would only change the child cwd and would not affect the interactive shell.

## Child launch

For a child command, `neosh` resolves the command, copies up to two arguments, allocates a resident child, sets launch id and arguments, commits the child, and waits for exit.
