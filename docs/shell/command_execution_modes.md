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

## File redirection

`neosh` executes file redirection for resident child-mode applets:

```text
command < input
command > output
command >> output
command 2> errors
command 2>> errors
```

The forms can be combined. The shell opens the requested files before
spawn, maps the temporary shell descriptors to child fd 0, 1, and 2
through `SYS_SPAWN_RESIDENT`, and closes all parent copies immediately
after the child has been published.

`<` opens an existing file read-only. `>` and `2>` create or truncate
their destination. `>>` and `2>>` create an absent file or preserve an
existing file and seek to end before spawn.

Opening the descriptor set is transactional: failure closes every
temporary descriptor opened for the command. Parent-mode commands such
as `cd` continue to reject redirection because they execute in the
shell process.
