# Spawn and Exec Model

NEOX uses a parent-controlled resident spawn model before implementing external executable loading.

## Parent-controlled setup

The parent performs setup in explicit steps:

```text
spawn_alloc_resident
optional fd setup
set launch id
set launch args
spawn_commit
waitpid
```

`spawn_abort` cancels a setup child before commit.

## Default inheritance

A newly allocated resident child inherits fd 0/1/2 by default:

```text
0 stdin
1 stdout
2 stderr
```

The parent may override child fds before commit.

## CWD inheritance

The child receives a snapshot of the parent current directory during allocation. The child can use that cwd independently after commit.

`CD` remains parent/direct because changing cwd in a child would not change the shell process cwd.

## Launch state

Resident applet launch uses compact launch state:

```text
launch id
argc
arg0
arg1
```

This is not a full process environment. It is only the minimal state needed to invoke resident applets in `nbox_child_entry`.

## Redirection and pipes

Redirection and pipes are parent-side fd setup before `spawn_commit`.

Important rule:

```text
The parent shell stdout is not modified.
Only the child fd table is changed.
```

For future `>`:

```text
neosh opens output file
neosh assigns child fd 1 to that file
neosh commits child
neosh waits/reaps child
```

For future `cmd1 | cmd2`:

```text
neosh creates pipe
cmd1 child fd 1 = pipe write end
cmd2 child fd 0 = pipe read end
parent closes its unneeded pipe copies
parent waits/reaps children
```
