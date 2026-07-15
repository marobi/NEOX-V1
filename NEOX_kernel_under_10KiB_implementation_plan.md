# NEOX Kernel Size Reduction Implementation Plan

## Objective

Reduce the NEOX kernel to **less than 10 KiB** while preserving the current core architecture and functionality.

### Size limits

- **Mandatory maximum:** 10,240 bytes
- **Preferred design target:** 9,500 bytes
- **Preferred working range:** 9.0–9.7 KiB

The target applies only to the **NEOX kernel build**.

The following are excluded from the kernel size target:

- BIOS, because it is a separate build
- syscall/user-space image
- `neosh`
- `nbox`
- applets
- RP2350 firmware
- generated or reference-only output

## Source-of-truth rules

For this work:

- Use the actual source files and build configuration in the latest `NEOX sources.zip`.
- Ignore `README.md`.
- Ignore documentation files for now.
- Ignore the separate `Unix-like OS Principles.txt`.
- Treat the `out` folder as reference-only.
- Do not modify files in `out`.
- Do not use generated output as authoritative when it conflicts with current source.
- The `out` folder does not contain BIOS build information.
- Measure the kernel from the actual NEOX kernel build target and linker inputs.
- Preserve preemptive-scheduling correctness.
- Temporary debug code must be enclosed in clearly marked removable debug sections.
- Do not introduce unprotected global scratch.

---

# Phase 0 — Establish a reproducible baseline

## Goal

Create a trustworthy size and functional baseline from the current sources before changing architecture.

## Work

1. Build the current NEOX kernel from a clean source tree.
2. Record:
   - kernel binary size;
   - linker map;
   - per-object ROM usage;
   - kernel RAM/BSS usage;
   - syscall table;
   - exported kernel entry points.
3. Confirm which object files are linked into the kernel target.
4. Confirm that no BIOS objects are part of the NEOX kernel build.
5. Add automated size reporting to the build.
6. Add:
   - warning at 9,500 bytes;
   - build failure above 10,240 bytes.
7. Freeze the current working build as the regression baseline.

## Validation

- Kernel boots.
- Timer IRQ works.
- Preemptive scheduling works.
- Console input/output works.
- Current filesystem smoke tests pass.
- Pipe blocking tests pass.
- Process creation, exit and wait still work.

## Deliverable

A reproducible baseline build with a reliable kernel-only size report.

---

# Phase 1 — Remove non-production and obsolete code

## Goal

Remove code that provides no required production functionality.

## Work

Audit actual sources for:

- temporary scheduler tracing;
- IRQ trace snapshots;
- verbose boot logging;
- obsolete test routines;
- superseded syscall paths;
- unused entry points;
- stale compatibility wrappers;
- old spawn helpers no longer called;
- dead condition branches;
- duplicate diagnostics.

Retain only compact panic or fatal-error output where required.

All temporary diagnostics retained during development must be surrounded by clearly marked debug comments.

## Expected reduction

Approximately **300–600 bytes**.

## Expected kernel size

Approximately **14.8–15.1 KiB**, depending on the rebuilt baseline.

## Validation

Repeat all Phase 0 regression tests.

---

# Phase 2 — Consolidate RP filesystem transport

## Goal

Replace repeated RP filesystem request wrappers with one generic mailbox transport path.

## Current problem

Separate routines for operations such as open, close, read, write, seek, tell, delete, rename, mkdir, rmdir, opendir and readdir repeat the same sequence:

1. acquire the RP resource;
2. prepare mailbox fields;
3. submit the request;
4. block or wait;
5. read status and results;
6. release the resource;
7. translate the result.

## Work

Create one common RP filesystem request routine.

The common transport should handle:

- RP gate or mailbox acquisition;
- command submission;
- process blocking;
- wake-up on completion;
- status retrieval;
- result retrieval;
- resource release;
- common error return.

Operation-specific code should only marshal fields that differ per command.

Do not introduce a spin lock. Waiting must follow the existing blocking/gate model.

## Expected reduction

Approximately **700–1,000 bytes**.

## Expected kernel size

Approximately **13.8–14.3 KiB**.

## Validation

Test:

- open and close;
- read and write;
- seek and tell;
- directory enumeration;
- create and delete;
- rename;
- RP error handling;
- timeout or recovery paths;
- multiple processes issuing filesystem calls.

---

# Phase 3 — Move pathname and CWD policy to the RP2350

## Goal

Remove filesystem-path policy from the 6502 kernel.

## Current problem

The kernel currently carries substantial code for:

- path parsing;
- path component scanning;
- slash normalization;
- relative-path handling;
- `.` handling;
- `..` handling;
- current-directory resolution;
- path validation;
- dual-path rename handling;
- filesystem-specific path preparation.

The RP2350 owns the filesystem and is the correct place for this work.

## Work

Move to the RP2350:

- pathname normalization;
- relative-to-absolute conversion;
- `.` and `..` processing;
- current-directory application;
- filesystem device-prefix handling;
- rename source and destination resolution;
- path-length and filesystem-specific validation;
- directory semantics.

The 6502 kernel should marshal only:

- operation;
- caller PID;
- raw path pointer;
- maximum path length;
- compact operation-specific arguments;
- process CWD identifier or handle.

## Preferred CWD model

Store a compact RP-owned CWD handle in the process state rather than a full canonical path in the 6502 kernel.

The RP2350 owns the canonical path.

Required RP-side operations may include:

- change current directory;
- retrieve current directory;
- open relative to process CWD;
- create relative to process CWD;
- rename relative to process CWD.

## Expected reduction

Approximately **2.0–2.8 KiB**.

## Expected kernel size

Approximately **11.0–12.3 KiB**.

## Validation

Test:

- absolute paths;
- relative paths;
- root directory;
- nested directories;
- `.` and `..`;
- process-specific CWD;
- repeated `chdir`;
- `getcwd`;
- invalid paths;
- oversized paths;
- rename using two relative paths.

---

# Phase 4 — Replace transactional spawn with one atomic syscall

## Goal

Replace the multi-call child-creation sequence with a compact atomic spawn request.

## Current problem

The current spawn subsystem contains separate operations for:

- process allocation;
- launch-ID setup;
- argument setup;
- FD inheritance;
- child-side duplication;
- child-side close;
- commit;
- abort.

This is flexible but ROM-expensive and creates half-constructed process states.

## Work

Introduce one syscall:

```text
spawn(request*)
```

The user-space request should contain only the information required to start the process, for example:

```c
struct spawn_request {
    uint16_t entry;
    uint16_t argument_pointer;
    uint8_t  argument_length;
    uint8_t  launch_id;
    uint8_t  stdin_fd;
    uint8_t  stdout_fd;
    uint8_t  stderr_fd;
    uint8_t  flags;
};
```

The kernel performs atomically:

1. validate the request;
2. allocate PID;
3. allocate context;
4. initialize the PCB;
5. map standard descriptors;
6. copy launch metadata;
7. construct the initial process stack;
8. mark the process runnable.

On failure, the kernel performs complete internal cleanup.

No half-created child is visible outside the syscall.

Initially support only standard descriptor mappings unless the current source proves more is required.

## Expected reduction

Approximately **600–900 bytes**.

## Expected kernel size

Approximately **10.2–11.5 KiB**.

## Validation

Test:

- resident `nbox_child_entry`;
- external executable entry;
- inherited console descriptors;
- pipe input;
- pipe output;
- invalid entry;
- no free process slot;
- no free context;
- FD mapping failure;
- cleanup after partial failure;
- child exit;
- parent wait.

---

# Phase 5 — Compact the FD subsystem

## Goal

Preserve correct FD and open-object semantics with fewer wrappers and less duplicated logic.

## Required functionality

Keep:

- per-process FD tables;
- shared open-object table;
- object type;
- access mode;
- reference count;
- object or device index;
- close-on-process-exit;
- `dup2`;
- pipe endpoint lifetime handling;
- inherited descriptor handling.

## Work

Consolidate the implementation around a small set of internal operations:

```text
fd_resolve(pid, fd)
fd_install(pid, object)
fd_dup2(pid, source, destination)
fd_close(pid, fd)
fd_close_all(pid)
```

Remove or merge:

- separate current-PID and arbitrary-PID wrappers;
- duplicate file, directory, read and write resolvers;
- multiple attachment helpers;
- multiple standard-FD cloning helpers;
- one-use wrappers;
- arbitrary-child setup operations made obsolete by atomic spawn.

Do not remove reference counting.

## Expected reduction

Approximately **400–700 bytes**.

## Expected kernel size

Approximately **9.6–10.8 KiB**.

## Validation

Test:

- descriptor allocation;
- descriptor reuse;
- invalid descriptors;
- `dup2`;
- inherited descriptors;
- shared file-object reference counts;
- close on process exit;
- pipe reader count;
- pipe writer count;
- cleanup on spawn failure.

---

# Phase 6 — Simplify pipe creation

## Goal

Keep pipe I/O and blocking in the kernel while reducing pipe setup code.

## Current problem

General cross-process pipe-creation and child-FD installation paths duplicate work that should be handled by:

- normal pipe creation in the parent;
- descriptor mapping in atomic spawn.

## Work

Retain one user-facing operation:

```text
pipe(fd_pair*)
```

It should:

1. allocate one pipe object;
2. allocate one read open-object;
3. allocate one write open-object;
4. allocate two descriptors in the calling process;
5. initialize endpoint counts;
6. return both descriptor numbers.

Remove or internalize:

- create-between-process operations;
- create-at-specific-child-FD operations;
- setup paths used only by the old spawn transaction.

Do not alter the pipe blocking semantics during this phase.

## Expected reduction

Approximately **300–500 bytes**.

## Expected kernel size

Approximately **9.1–10.3 KiB**.

## Validation

Test:

- basic read/write;
- empty pipe read blocking;
- full pipe write blocking;
- reader wake-up;
- writer wake-up;
- EOF after the final writer closes;
- broken pipe after the final reader closes;
- inherited endpoints;
- child exit;
- process termination while blocked.

---

# Phase 7 — Consolidate blocking syscall state

## Goal

Store pending syscall state once per process and share common read/write continuation logic.

## Current problem

Blocking I/O state may be spread across parallel arrays and operation-specific scratch.

This increases ROM, RAM and preemption risk.

## Work

Use compact per-process pending-I/O state, either inside the PCB or in dedicated per-process storage:

```text
pending_operation
pending_object
pending_buffer
pending_length
pending_result
```

Create one common flow:

1. validate syscall arguments;
2. resolve the FD;
3. dispatch by object type;
4. perform the operation or block;
5. preserve state in the process;
6. resume safely;
7. return the result.

Console, pipe and RP filesystem backends remain separate, but their syscall setup and continuation handling should be shared.

Use `active_pid` only where the currently executing process identity is required.

Do not use unsafe global scratch.

## Expected reduction

Approximately **100–250 bytes**.

## Expected kernel size

Approximately **8.9–10.1 KiB**.

## Validation

Test:

- console read blocking;
- pipe read blocking;
- pipe write blocking;
- RP filesystem completion;
- syscall interruption;
- preemption during read/write;
- resumed syscall state;
- no cross-process scratch corruption;
- correct process ownership.

---

# Phase 8 — Scheduler and context-switch size pass

## Goal

Reduce duplicate scheduler paths without changing the scheduling model.

## Rules

Preserve:

- preemptive scheduling;
- `active_pid`;
- `active_context`;
- `console_owner_pid`;
- IRQ ownership;
- process state transitions;
- blocking and wake-up reasons;
- first process start;
- supervisor transitions;
- context control;
- timer-expiry behavior.

## Work

Audit for common tails and duplicated operations across:

- timer preemption;
- voluntary yield;
- block-current;
- process exit;
- idle transition;
- first process start;
- resumed process start.

Potential reductions:

- one next-process selector;
- one shared context-load path;
- one common scheduler-entry tail;
- prebuilt initial process stacks;
- removal of unused scheduler accounting;
- removal of production trace updates;
- compact state handling;
- common error and idle paths.

Do not rewrite scheduler logic based on abstract assumptions. Use the actual current source procedures and labels.

## Expected reduction

Approximately **150–300 bytes**.

## Expected kernel size

Approximately **8.7–9.9 KiB**.

## Validation

Run extended tests:

- repeated timer preemption;
- rapid yield loop;
- repeated block/wake cycles;
- idle-to-runnable transitions;
- process exit during scheduling;
- first-run stack setup;
- console-owner changes;
- foreground `^C`;
- IRQ acknowledgement;
- timer-expiry wake/resume;
- stack integrity for every process.

---

# Phase 9 — Final code-size optimization

## Goal

Reach the final size target after the architectural work is stable.

## Work

Use the final linker map and listings to optimize only proven large procedures.

Apply where safe:

- common error-return labels;
- common success-return labels;
- tail merging;
- removal of unnecessary save/restore sequences;
- 65C02 instructions where smaller;
- compact loops;
- elimination of one-use wrappers;
- shared parameter-copy routines;
- compact syscall dispatch;
- shorter constant handling;
- removal of unused strings;
- shared validation paths;
- table-driven logic only when smaller than branching.

Do not:

- compromise preemptive correctness;
- introduce unprotected global scratch;
- remove required failure cleanup;
- merge paths whose stack or interrupt states differ;
- optimize generated reference output instead of source.

## Expected reduction

Approximately **200–500 bytes**.

## Final expected kernel size

Approximately **9.0–9.7 KiB**.

---

# Version sequence

| Version | Main change | Expected kernel size |
|---|---|---:|
| V1 | Baseline and production-code cleanup | 14.8–15.1 KiB |
| V2 | Generic RP filesystem transport | 13.8–14.3 KiB |
| V3 | RP-owned pathname and CWD resolution | 11.0–12.3 KiB |
| V4 | Atomic spawn syscall | 10.2–11.5 KiB |
| V5 | Compact FD layer | 9.6–10.8 KiB |
| V6 | Compact pipe creation | 9.1–10.3 KiB |
| V7 | Unified blocking I/O state | 8.9–10.1 KiB |
| V8 | Scheduler and final ROM pass | 9.0–9.7 KiB |

Each version must remain independently buildable and testable.

Do not combine the filesystem, spawn, FD, pipe and scheduler redesigns into one large change.

---

# Acceptance criteria

The reduction work is complete when the rebuilt NEOX kernel satisfies:

```text
Kernel ROM < 10,240 bytes mandatory
Kernel ROM <= 9,500 bytes preferred
```

and the following still work:

- preemptive scheduling;
- timer IRQ;
- context switching;
- process blocking and wake-up;
- console ownership;
- foreground-process interruption with `^C`;
- signal delivery;
- console input/output;
- blocking pipe input/output;
- FD inheritance;
- `dup2`;
- pipe lifetime handling;
- resident applet spawning;
- external executable startup;
- filesystem access through the RP2350;
- process-specific current directory;
- process exit;
- zombie state;
- wait handling;
- failure cleanup without leaked:
  - processes;
  - contexts;
  - FDs;
  - open objects;
  - pipe references;
  - RP resource ownership.

---

# Implementation discipline

For every phase:

1. Inspect the actual current source.
2. Identify concrete procedures, labels, tables and call sites.
3. Produce a size report before and after the change.
4. Remove superseded code completely.
5. Keep temporary diagnostics inside clearly marked debug blocks.
6. Rebuild from clean sources.
7. Run the phase-specific regression tests.
8. Retain a working version before starting the next phase.
9. Update the kernel-size budget.
10. Stop and investigate any correctness regression before continuing.

The primary objective is a structurally smaller kernel, not merely instruction-level compression of the current design.
