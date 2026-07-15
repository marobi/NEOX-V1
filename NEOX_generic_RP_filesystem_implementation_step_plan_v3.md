# NEOX Generic RP Filesystem Offload — Implementation Step Plan

## 1. Objective

Move filesystem-heavy work from the 6502 kernel to the RP2350 and reduce the NEOX kernel ROM size without removing filesystem functionality.

Starting validated Phase 1 baseline:

```text
Kernel ROM:           14,458 bytes
ksys_fs.o:             3,474 bytes
rp_fs_io.o:            1,333 bytes
process_cwd.o:           142 bytes
Shared-state ABI:       0x0207
Kernel base:            $6000
```

Mandatory project target:

```text
Kernel ROM < 10,240 bytes
```

This filesystem phase is expected to remove approximately:

```text
2.5–3.5 KiB
```

The exact result must be measured. This phase alone may not reach the final 10 KiB target. Any remaining reduction must come from later consolidation, not by deleting working syscalls or reducing filesystem behavior.

---

# 2. Non-negotiable functionality

The following functionality must remain available:

- all existing filesystem syscalls;
- all five current open modes;
- normal FD ownership and permission checking;
- file read and write;
- seek and tell with 32-bit positions;
- delete and rename;
- opendir, readdir, and closedir;
- chdir and getcwd;
- mkdir and rmdir;
- bulk load and save;
- per-process current directories;
- relative and absolute paths;
- `.` and `..`;
- device selection;
- NEOX 8.3 validation;
- process FD inheritance;
- process exit and zombie cleanup;
- console and pipe I/O;
- monitor entry and exit;
- preemptive scheduling;
- useful `ps` diagnostics.

Moving functionality to the RP2350 is allowed. Removing or weakening it to save kernel ROM is not.

---

# 3. Size-first implementation rules

## 3.1 Replace; do not accumulate

A completed migration step must remove the superseded 6502 code.

Do not leave both complete implementations in the kernel after a step is validated.

Temporary dual paths are allowed only inside an unfinished development step.

## 3.2 RP firmware growth is acceptable

The size target applies to the NEOX 6502 kernel, not the RP2350 firmware.

Path resolution, validation, CWD storage, FatFs argument handling, and data copying should move to the RP even when this increases RP firmware size.

## 3.3 Preserve the user syscall ABI

Do not change:

- syscall numbers;
- user-visible argument structures;
- FD numbering;
- return register conventions;
- existing open flags;
- current directory text format;
- existing success and error semantics unless correcting a proven bug.

## 3.4 Reuse the existing mailbox block

Do not add a separate 16-byte generic request descriptor.

The current mailbox block already contains enough fields. Reusing it saves both shared memory and 6502 setup code.

## 3.5 Avoid new shared kernel scratch

Per-call state should use:

- the caller’s private stack;
- process-private `BSS`;
- the mailbox request;
- RP-local memory.

Do not add operation-specific arrays or large shared scratch blocks to `KERN_BSS`.

## 3.6 Measure size at phase completion

Do not measure or optimize kernel size after every implementation step.

Intermediate steps may temporarily add infrastructure or retain compatibility code. Functional correctness and complete migration take priority during the phase.

Measure kernel ROM, object-module sizes, KERN_BSS, and shared-state usage once after the complete phase has been implemented and legacy code has been removed.

---

# 4. Agreed execution and failure model

## 4.1 One active filesystem request

Only one RP filesystem request may be active.

## 4.2 Gate ownership

The requesting process acquires `file_io_gate` and remains its owner for the complete RP transaction:

```text
acquire file_io_gate
validate FD and kernel-owned metadata
publish generic request
block in WAIT_RP while still owning file_io_gate
RP completes
owner wakes
collect result
release file_io_gate
```

Other filesystem callers wait in:

```text
WAIT_LOCK / LOCK_ID_FILE_IO
```

## 4.3 No timeout or cancellation

The first implementation has no:

- timeout;
- watchdog;
- request cancellation;
- forced gate release;
- RP filesystem reset protocol.

If the RP never completes, filesystem-dependent activity remains blocked.

The recovery path is a system reset.

## 4.4 SIG_KILL

`SIG_KILL` is not a recovery mechanism for an active RP request.

A kill targeting a process that currently owns a kernel gate must not turn that process into a zombie while the gate remains held.

For the first implementation:

```text
target owns file_io_gate or proc_gate
and signal is SIG_KILL
    -> reject with EAGAIN
```

The signal is not queued.

A process waiting to acquire a gate is not a gate owner. Killing such a waiter must remove it from the gate FIFO before it becomes a zombie.

## 4.5 SIG_HALT

A pending `SIG_HALT` must not stop a process while it owns `file_io_gate` or `proc_gate`.

The signal remains pending until the process releases its gates.

This prevents a completed RP request from waking a process that is then stopped before it can release `file_io_gate`.

---

# 5. Compact generic mailbox request

## 5.1 Existing mailbox fields

Use the existing ABI-v2 fields:

```text
RP_GROUP
RP_CMD
RP_STATUS
RP_ERR
RP_FLAGS
RP_STATE
RP_ARG0L/H
RP_ARG1L/H
RP_ARG2L/H
RP_RES0L/H
RP_RES1L/H
```

## 5.2 Generic command

Add:

```text
RP_GROUP = RP_GROUP_FS
RP_CMD   = RP_FS_CMD_EXEC
```

## 5.3 Request-field mapping

```text
RP_STATE     = filesystem operation
RP_ARG0L/H   = pointer to existing syscall argument block
RP_ARG1L     = requesting or target PID
RP_ARG1H     = trusted MMU context
RP_ARG2L     = rp_handle, or $FF when not applicable
RP_ARG2H     = operation-specific auxiliary byte
RP_FLAGS     = request flags; overwritten by result flags
```

Results remain:

```text
RP_ERR
RP_FLAGS
RP_RES0L/H
RP_RES1L/H
```

## 5.4 Deliberately omitted fields

Do not add:

- request ID;
- argument-block size;
- duplicate device field;
- duplicate length fields;
- duplicate buffer pointers.

Reasons:

- only one request is active;
- the operation determines the exact argument structure and size;
- the RP reads device, path, length, and buffer fields from the existing syscall argument block;
- `file_io_gate_owner` identifies the active transaction owner.

## 5.5 `rp_handle`

For FD-based operations the kernel resolves the user FD and supplies the opaque RP handle:

```text
read
write
seek
tell
close
readdir
closedir
```

For path-based operations:

```text
rp_handle = $FF
```

The RP must ignore the user-supplied FD value after the kernel has supplied `rp_handle`.

---

# 6. Step 0 — Completed and frozen

## Status

Completed and already validated. No further work or measurement is required in this step.

## Goal

Maintain the validated Phase 1 baseline as the reference point before changing the protocol.

## Work

Use the validated Phase 1 Step 9 source set:

- Step 7 NEOX sources;
- matching RP source;
- corrected MICMON source;
- shared-state ABI `0x0207`;
- kernel base `$6000`;
- final validated `out.zip` for comparison only.

Record:

- complete linker map;
- object-module sizes;
- KERN_BSS usage;
- shared-state usage;
- current syscall regression results.

Enforce the temporary memory boundaries:

```text
KERN:    $6100–$AFFF
PRIVRAM: $0280–$5FFF
USER:    $2000–$5FFF
```

## Completed validation

The complete baseline smoke test has already been run:

- boot;
- timer IRQ;
- scheduling;
- console;
- file open/read/write/close;
- seek/tell;
- delete/rename;
- directory operations;
- CWD;
- mkdir/rmdir;
- load/save;
- pipe blocking;
- spawn/wait/zombie;
- monitor enter/exit.

## Baseline result

```text
Kernel ROM: 14,458 bytes
Shared-state ABI: 0x0207
Kernel base: $6000
```

Execution of this implementation plan therefore starts at Step 1.

---

# 7. Step 1 — Make gate-held RP blocking schedulable

## Goal

Allow a process to block while retaining `file_io_gate` without stopping preemptive scheduling for unrelated processes.

## Current issue

`irq.asm` currently suppresses timer context switches whenever:

```text
file_io_gate
proc_gate
rp_lock
```

is non-zero.

That was a workaround for module-global syscall scratch and conflicts with a blocked gate owner.

## Work

### 7.1 Audit gate-protected scratch

Verify that all accesses to shared scratch protected by `file_io_gate` or `proc_gate` occur only while the relevant gate is owned.

Audit at least:

```text
kernel/ksys_fs.asm
kernel/ksys_io.asm
kernel/fd.asm
kernel/pipe.asm
kernel/process_control.asm
kernel/spawn.asm
kernel/gate.asm
```

Correct any unprotected access before changing IRQ policy.

### 7.2 Update preemption policy

Permit timer scheduling while a gate is owned.

The gate itself prevents another process from entering the protected subsystem.

Keep `sched_lock` as the scheduler re-entry guard.

`rp_lock` may remain temporarily until Step 10, but it must not be required by the new generic FS path.

### 7.3 Update gate documentation

Change the gate invariant from:

```text
no gate may be held across sched_yield
```

to:

```text
file_io_gate and proc_gate may remain owned across WAIT_RP only
```

Normal pipe, console, timer, and lock waits continue using their existing rules.

## Functional validation

Use an artificial RP delay and verify:

- the gate owner blocks;
- a CPU-only process continues to receive time slices;
- a filesystem waiter enters `WAIT_LOCK`;
- no protected scratch is corrupted;
- pipe and console behavior remains unchanged;
- monitor enter/exit still works.


Removing obsolete IRQ gate tests may recover some bytes.

---

# 8. Step 2 — Add WAIT_RP, completion IRQ, signal safety, and PS visibility

## Goal

Implement the lifecycle around an RP request before migrating filesystem operations.

## Work

### 8.1 Add the wait reason

In `include/process.inc`:

```text
WAIT_RP = $08
```

Use:

```text
wait_reason = WAIT_RP
wait_object = filesystem operation
```

No request ID is needed because there is only one active request.

### 8.2 Add an RP completion interrupt source

Add:

```text
RP_SRC_FS_DONE
```

to both 6502 and RP definitions.

The current RP IRQ generator permits only one outstanding IRQ source. Do not replace it with a larger interrupt subsystem.

Instead:

1. set an RP-local `fs_completion_pending` flag when the request finishes;
2. retry `genIRQ6502(RP_SRC_FS_DONE)` until accepted;
3. clear the flag only after the completion IRQ has been generated.

A timer or monitor IRQ may delay the completion IRQ, but must not cause it to be lost.

### 8.3 Wake the gate owner

The 6502 FS-completion IRQ path:

1. reads `file_io_gate_owner`;
2. verifies that the owner is valid;
3. verifies `PROC_BLOCKED`;
4. verifies `WAIT_RP`;
5. wakes the owner;
6. enters the scheduler without incrementing the timer tick.

The IRQ does not:

- release `file_io_gate`;
- mark the mailbox idle;
- read operation results;
- submit another request.

### 8.4 Protect gate owners from signals

Update signal handling:

- reject `SIG_KILL` with `EAGAIN` when the target owns `file_io_gate` or `proc_gate`;
- do not apply `SIG_HALT` while the target owns either gate;
- allow the signal to be applied after gate release;
- remove killed `WAIT_LOCK` processes from the correct gate FIFO.

### 8.5 Extend process information

Extend `SYS_GETPROCINFO` with:

```text
wait_object
held_gate_mask
```

Suggested bits:

```text
PROC_HOLD_FILE_IO = $01
PROC_HOLD_PROC    = $02
```

This is a syscall result extension, not a new shared-state field.

### 8.6 Update `nbox ps`

Display enough information to distinguish:

```text
PID 3: WAIT=RP,  OBJ=<operation>, HOLD=FIO
PID 5: WAIT=LCK, OBJ=FIO,         HOLD=-
PID 7: WAIT=LCK, OBJ=FIO,         HOLD=-
```

The RP debug process display must use the same wait-reason constants and show the same distinction.

## Functional validation

With an artificial RP delay:

- one process must show `WAIT_RP` and `HOLD=FIO`;
- at least two other processes must show `WAIT_LOCK/FIO`;
- FIFO order must remain correct;
- `SIG_KILL` against the owner must return `EAGAIN`;
- `SIG_HALT` against the owner must not stop it before gate release;
- killing a gate waiter must not leave a stale FIFO entry;
- completion must wake the correct owner;
- timer and monitor IRQs must continue working.


Do not freeze this as a long-term phase endpoint. Proceed directly to generic-wrapper removal.

---

# 9. Step 3 — Implement the compact generic transport

## Goal

Replace the many operation-specific mailbox transaction sequences with one blocking transport.

## 6502 work

Create one routine, for example:

```text
rp_fs_exec
```

Contract:

```text
Caller owns file_io_gate.

Inputs:
    operation
    syscall argument-block pointer
    trusted PID/context
    rp_handle
    auxiliary byte

Success:
    C clear
    A/X = RES0
    additional result in RES1 or caller argument block

Failure:
    C set
    Y = errno
```

Sequence:

1. verify `RP_STATUS == RP_IDLE`;
2. clear request/result fields;
3. fill the compact generic request;
4. disable IRQs;
5. set the current process to `WAIT_RP`;
6. set `RP_STATUS = RP_BUSY`;
7. ring the doorbell;
8. enter the scheduler while retaining `file_io_gate`;
9. resume after the completion IRQ;
10. read result/error;
11. set `RP_STATUS = RP_IDLE`;
12. return to the syscall wrapper;
13. wrapper releases `file_io_gate`.

The process wait state must be committed before the doorbell is rung so an immediate RP completion cannot be lost.

### PID 0 exception

PID 0 cannot resume a blocked syscall continuation.

When `active_pid == 0`, use the same generic request but poll for completion instead of entering `WAIT_RP`.

This path is required for idle-side zombie cleanup and boot-time service calls.

It is not a second filesystem implementation; it is only a second wait method around the same request.

## RP work

Add:

```text
rp_fs_mailbox_handle_exec()
```

It:

1. reads the generic request;
2. validates the operation;
3. validates PID and context;
4. decodes the corresponding existing syscall argument block;
5. executes the operation;
6. writes output data;
7. writes result/error;
8. writes `RP_DONE` or `RP_ERROR` last;
9. queues `RP_SRC_FS_DONE`.

Initially implement only a harmless operation such as filesystem status.

Keep legacy handlers temporarily for all unmigrated operations.

## Functional validation

Test:

- normal process blocking;
- PID 0 polling;
- successful completion;
- RP error completion;
- immediate completion;
- delayed completion;
- timer IRQ arriving first;
- monitor IRQ arriving first;
- completion IRQ retry;
- mailbox idle transition.


The generic transport must remain compact enough that deleting two or three legacy wrappers makes the kernel smaller than the Step 2 build.

---

# 10. Step 4 — Build the RP-owned path and CWD engine

## Goal

Complete the heavy RP-side functionality before removing the kernel resolver.

This step changes primarily RP firmware and should not increase kernel ROM.

## RP CWD table

Create one RP-local entry per PID:

```text
valid
device
canonical path
```

Canonical rules:

- root is represented consistently;
- no redundant separators;
- no `.` components;
- `..` never escapes root;
- device is stored separately;
- path components obey NEOX 8.3 rules.

## Required path behavior

Preserve the existing meanings of:

```text
N:/PATH
/PATH
PATH
.
..
```

Both rename paths resolve relative to the same process CWD unless either path explicitly selects a device/root.

## CWD lifecycle

Implement:

```text
CWD_INIT_ROOT
CWD_CLONE
```

Do not add `CWD_DROP` in the first implementation.

A stale CWD entry for an empty PID is harmless because every PID allocation must overwrite it with INIT or CLONE before the process becomes runnable.

Omitting DROP:

- saves kernel and RP protocol code;
- avoids an additional RP call during process cleanup;
- does not change user-visible functionality.

## RP unit validation

Before kernel cutover, test:

- root;
- nested directories;
- repeated separators;
- `.`;
- `..`;
- attempted escape above root;
- explicit device paths;
- absolute paths;
- relative paths;
- two-path rename;
- invalid 8.3 components;
- maximum path length;
- independent CWD values for multiple PIDs;
- CWD clone.


---

# 11. Step 5 — Migrate all pathname and CWD syscalls

## Goal

Move every pathname consumer before deleting the kernel resolver.

## Operations

Migrate:

```text
open
delete
rename
opendir
chdir
getcwd
mkdir
rmdir
load
save
```

## Kernel behavior retained

The kernel still owns:

- FD allocation;
- open-object allocation;
- open flags;
- object type;
- RP handle storage;
- rollback after failed open/opendir;
- syscall result convention.

For `open` and `opendir`:

1. reserve the kernel FD/open object while holding `file_io_gate`;
2. call the generic RP request;
3. commit the returned RP handle on success;
4. release reservations on failure;
5. release the gate.

## CWD integration

During process allocation:

- root-initialize system processes;
- clone the parent CWD for spawned children;
- complete CWD setup before marking the child runnable.

Do not perform CWD cleanup on exit. PID reuse overwrites the RP CWD entry.

## Delete superseded kernel code immediately

After all pathname consumers use the RP engine, remove:

```text
ksys_cwd_select_current
ksys_resolve_clear
ksys_resolve_append_char
ksys_resolve_append_slash_if_needed
ksys_resolve_copy_cwd
ksys_resolve_remove_last_component
ksys_resolve_commit_component
ksys_resolve_path
ksys_set_cwd_from_resolved
```

Remove all associated resolver scratch, including:

```text
ksys_resolved_path
ksys_rename_old_resolved_path
ksys_component_buf
resolver indexes and lengths
kernel CWD assembly buffers
```

Remove:

```text
kernel/process_cwd.asm
```

Remove shared CWD mirrors only after all RP debug and lifecycle users are migrated:

```text
proc_cwd_shared_device
proc_cwd_shared_len
proc_cwd_shared_path
```

A shared-state ABI bump is required when these fields are removed. Update the RP mirror in the same step.

## Legacy wrapper deletion

Delete the corresponding operation-specific routines from `rp_fs_io.asm` as soon as their generic replacements are validated.

Do not retain compatibility wrappers that have no remaining callers.

## Functional validation

Run the complete pathname matrix:

- every open mode;
- current device selection;
- root and relative paths;
- `.` and `..`;
- chdir/getcwd;
- mkdir/rmdir;
- rename old/new relative paths;
- process-specific CWD;
- child CWD inheritance;
- failed open rollback;
- failed opendir rollback;
- load/save full-range behavior;
- invalid path and buffer errors.


This is the principal size-saving step.

---

# 12. Step 6 — Migrate directory and position operations

## Goal

Remove remaining specialized wrappers that operate on an already-resolved RP handle.

## Operations

Migrate:

```text
seek
tell
readdir
closedir
```

## Rules

- kernel validates FD type and access;
- kernel supplies `rp_handle`;
- RP ignores the FD byte in user memory;
- RP writes 32-bit seek/tell results into the existing argument block;
- RP writes directory entries directly into the caller buffer;
- EOF behavior remains unchanged;
- close of the final directory reference still releases the RP directory handle.

## Delete superseded code

Remove:

- operation-specific mailbox setup;
- seek/tell result scratch;
- readdir marshalling scratch;
- closedir wrappers;
- now-unused imports and aliases.

## Functional validation

Test:

- SEEK_SET, SEEK_CUR, SEEK_END;
- positive and negative offsets;
- invalid target offsets;
- 32-bit tell;
- repeated readdir;
- end-of-directory;
- too-small directory-entry buffer;
- dup/dup2 references to directory objects where currently supported;
- final closedir behavior.


---

# 13. Step 7 — Migrate file read, write, and close

## Goal

Move ordinary file transfer argument decoding to the RP while preserving console and pipe behavior.

## `SYS_READ` and `SYS_WRITE`

Keep the current unified syscalls.

The kernel still:

1. acquires `file_io_gate`;
2. resolves FD;
3. checks access;
4. classifies object type.

For:

```text
OBJ_FILE
```

the kernel passes:

```text
operation
original rw_args pointer
rp_handle
PID/context
```

to the generic RP request.

For:

```text
OBJ_PIPE
OBJ_DEVICE
```

retain the current pipe and console paths unchanged.

## Simplify argument snapshots

The syscall argument block is private to the blocked process and cannot be changed by another process.

Replace the current per-PID copied read/write fields:

```text
fd
buffer pointer
length
```

with one process-private saved argument-block pointer.

Preferred storage:

```text
private BSS, two bytes per context
```

or the private process stack where the resulting code is smaller.

Do not retain five copied fields per PID after the direct-pointer model is active.

## Close

When the final kernel reference to a file object is closed:

- call generic RP close while retaining `file_io_gate`;
- free the open object after completion;
- use PID 0 polling during idle reaping.

The same logic must work for:

- explicit close;
- dup/dup2 final reference;
- normal process exit;
- waitpid reaping;
- orphan zombie reaping;
- spawn abort.

## Functional validation

Test:

- file read/write;
- partial transfers;
- EOF;
- zero-length transfer;
- invalid buffers;
- concurrent filesystem callers;
- console read/write;
- pipe read/write and blocking;
- dup/dup2;
- last-reference close;
- process exit with open files;
- SIG_KILL of a non-owner process with open files;
- idle zombie cleanup;
- spawn abort cleanup.


---

# 14. Step 8 — Remove the legacy filesystem transport

## Goal

Leave one generic filesystem transaction implementation in the kernel.

## Remove from `rp_fs_io.asm`

Remove all operation-specific exports and routines such as:

```text
rp_fs_open_*
rp_fs_read
rp_fs_write
rp_fs_seek
rp_fs_tell
rp_fs_delete
rp_fs_rename
rp_fs_opendir
rp_fs_readdir
rp_fs_closedir
rp_fs_mkdir
rp_fs_rmdir
rp_fs_load_file_to_memory
rp_fs_save_memory_to_file
rp_fs_close
```

Retain only the compact generic transport and any genuinely common result helper.

Rename the source module if useful:

```text
rp_fs_request.asm
```

Do not retain forwarding wrappers solely to preserve old internal names.

Internal kernel procedure names are not a public ABI.

## Remove obsolete scratch

Delete all unused:

- operation-specific mailbox scratch;
- path snapshots;
- result-high scratch;
- rename secondary-path scratch;
- bulk-call preparation scratch;
- aliases whose only callers have been removed.

## RP cleanup

Remove legacy mailbox command handlers after all operations use `RP_FS_CMD_EXEC`.

The old command constants may remain temporarily only when monitor tools still require them. Remove them when no caller remains.

## Functional validation

Repeat the entire filesystem and process regression matrix.


---

# 15. Step 9 — Remove redundant `rp_lock`

## Goal

Use `file_io_gate` as the sole 6502-side serializer for mailbox I/O.

## Precondition

Prove that every 6502 mailbox request is reached while `file_io_gate` is owned:

- filesystem;
- console read;
- console write;
- any system mailbox command still present.

MICMON and IRQ code must not submit mailbox requests.

## Work

Remove:

```text
rp_lock
rp_try_acquire_lock
rp_acquire_lock
rp_release_lock
```

Update:

```text
kernel/mailbox.asm
kernel/rp_console_io.asm
kernel/irq.asm
kernel/shared_state.asm
```

Console requests remain serialized because console dispatch already occurs through `file_io_gate`.

The RP-side direct monitor filesystem commands use their own RP-local filesystem mutex and do not use the 6502 mailbox lock.

A shared-state ABI bump is required if `rp_lock` is removed from shared state.

## Functional validation

Test:

- console read/write;
- filesystem request active while another process attempts console output;
- FIFO gate wake order;
- monitor entry/exit during RP filesystem work;
- mailbox state never overwritten;
- no mailbox request starts while `RP_STATUS != RP_IDLE`.


The exact saving depends on linker elimination and remaining mailbox users.

---

# 16. Step 10 — Final size cleanup without feature removal

## Goal

Remove code and storage made obsolete by the completed architecture.

## Audit

Check for:

- unused imports and exports;
- dead legacy command constants;
- duplicate result-copy helpers;
- duplicated errno translation;
- no-longer-used path flags;
- no-longer-used CWD helpers;
- dead per-PID snapshots;
- obsolete comments and conditional branches;
- unreachable error cleanup;
- shared-state mirror fields no longer used by RP diagnostics.

Use the linker map and symbol references, not documentation, as authority.

## Do not remove

Do not remove working:

- syscalls;
- open modes;
- directory support;
- CWD support;
- load/save;
- process cleanup;
- diagnostics required to identify blocked gate ownership.


---

# 17. Step 11 — Final validation and freeze

## Required functional matrix

### Filesystem

- status;
- all open modes;
- read/write/close;
- seek/tell;
- delete/rename;
- opendir/readdir/closedir;
- chdir/getcwd;
- mkdir/rmdir;
- load/save;
- multiple devices;
- error paths;
- invalid pointers;
- maximum lengths.

### Concurrency

- owner blocked in `WAIT_RP`;
- several FIFO `WAIT_LOCK/FIO` waiters;
- CPU-only process remains preemptive;
- console and pipe behavior unchanged;
- completion IRQ delayed by timer IRQ;
- completion IRQ delayed by monitor IRQ;
- no lost wake-up;
- no stale gate waiter after kill.

### Process lifecycle

- normal exit with open files;
- child zombie with open files;
- waitpid cleanup;
- orphan reaping through PID 0 polling;
- spawn CWD inheritance;
- spawn abort;
- dup/dup2 final-reference close;
- SIG_HALT while RP owner blocked;
- SIG_KILL against RP owner returns `EAGAIN`;
- SIG_KILL against a gate waiter removes it cleanly.

### Monitor

Mandatory after every IRQ/shared-layout step:

- enter monitor;
- inspect process/gate state;
- leave monitor;
- resume the correct process;
- complete the RP request;
- verify scheduler and timer still function.

## Final size report

Record:

```text
Phase 1 baseline kernel ROM
final kernel ROM
total reduction
per-module before/after sizes
KERN_BSS before/after
shared-state before/after
remaining bytes to 10 KiB
```

## Freeze criteria

The phase is accepted only when:

1. all existing filesystem functionality passes;
2. concurrency and gate ownership are correct;
3. `ps` clearly identifies owner and waiters;
4. process cleanup does not leak RP handles;
5. monitor entry/exit passes;
6. kernel size is materially reduced;
7. no legacy duplicate filesystem implementation remains.

---

# 18. Phase-end size measurement

Size is measured only after:

- all filesystem operations use the generic RP request;
- RP-owned path and CWD handling is complete;
- legacy 6502 filesystem wrappers are removed;
- obsolete scratch and shared-state fields are removed;
- redundant locking code has been removed where proven safe;
- the complete regression matrix passes.

Record at phase completion:

```text
Phase 1 baseline kernel ROM
final phase kernel ROM
total ROM reduction
per-module before/after sizes
KERN_BSS before/after
shared-state before/after
remaining bytes to the 10 KiB target
```

The phase objective remains maximum kernel-size reduction without removing filesystem functionality.
