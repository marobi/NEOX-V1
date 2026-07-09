# Process Management

The NEOX process model is small and explicit. Processes have kernel-owned state and may be associated with a preloaded context or a later externally loaded image.

## Process lifecycle

```text
PROC_EMPTY
  -> PROC_SETUP
  -> PROC_NEW
  -> PROC_READY / PROC_RUNNING / PROC_BLOCKED
  -> PROC_ZOMBIE
  -> PROC_EMPTY
```

## PROC_SETUP

`PROC_SETUP` represents a child that has been allocated but is not runnable yet. It exists so the parent can safely configure the child before commit:

- fd inheritance/overrides
- cwd snapshot
- launch id
- launch arguments
- entry point

Only the parent may configure, commit, or abort a setup child.

## Commit

`spawn_commit` makes the child runnable. Before commit, the child must not be scheduled as a normal runnable process.

## Exit and zombie state

A child with a live parent becomes `PROC_ZOMBIE` when it exits. Its exit status remains available until the parent calls `waitpid`.

A zombie is not runnable. Its fd table is closed during exit. Its PID and context ownership remain until it is reaped.

## Reap

`waitpid` reaps a child zombie owned by the caller and returns the exit code. Reaping releases the PID/context resources.

## Orphans and system cleanup

The kernel/idle reaper may clean up zombies that have no live normal parent. It must not reap a child that still has a live parent expected to call `waitpid`.
