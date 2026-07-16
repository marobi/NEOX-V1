# Process Management

The NEOX process model is small and explicit. Processes have kernel-owned state and may be associated with a preloaded context or a later externally loaded image.

## Process lifecycle

```text
PROC_EMPTY
  -> PROC_NEW
  -> PROC_READY / PROC_RUNNING / PROC_BLOCKED
  -> PROC_ZOMBIE
  -> PROC_EMPTY
```

## Unpublished creation

Unified resident spawn allocates and initializes a PID/context while
`proc_gate` is held, but leaves `proc_state` as `PROC_EMPTY`. The slot
is invisible to the scheduler and lifecycle syscalls until the
transaction publishes it as `PROC_NEW`.

## Publication

Unified spawn publishes the fully initialized child as `PROC_NEW` only after launch data, descriptors, and cwd are installed.

## Exit and zombie state

A child with a live parent becomes `PROC_ZOMBIE` when it exits. Its exit status remains available until the parent calls `waitpid`.

A zombie is not runnable. Its fd table is closed during exit. Its PID and context ownership remain until it is reaped.

## Reap

`waitpid` reaps a child zombie owned by the caller and returns the exit code. Reaping releases the PID/context resources.

## Orphans and system cleanup

The kernel/idle reaper may clean up zombies that have no live normal parent. It must not reap a child that still has a live parent expected to call `waitpid`.
