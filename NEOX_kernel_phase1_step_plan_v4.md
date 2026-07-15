# NEOX Kernel Reduction — Phase 1 Step Plan

## Objective

Phase 1 concentrates on removing **superfluous debugging code and debugging data** from four kernel areas:

1. scheduler;
2. timer;
3. pipe;
4. filesystem.

This phase does not redesign these subsystems. It removes only diagnostic instrumentation, obsolete snapshots, unused counters, stale debug initialization, and associated storage.

`klog` remains unchanged during this phase.

Foreground `^C` processing is not implemented yet and is excluded from validation.

## Source rules

Use the latest uploaded NEOX source tree.

- Ignore `README.md`.
- Ignore documentation files for now.
- Treat `out/` as reference-only.
- Do not modify generated files in `out/`.
- BIOS is a separate build.
- The `out/` folder contains no BIOS information.
- Preserve current runtime behavior.
- Do not introduce unprotected global scratch.

---

# Prerequisite — Record the current size

Before removing code, perform one clean NEOX kernel build and record:

- kernel binary size;
- `KERN_TEXT` size;
- `KERNEL_ENTRY` size;
- kernel BSS usage;
- zero-page usage;
- per-object ROM usage.

Phase 0 functional validation is already established. This prerequisite provides only the size baseline.

---

# Step 1 — Build a debug-code and debug-data inventory

## Files to inspect

### Scheduler

- `kernel/scheduler.asm`
- scheduler-related state in `kernel/shared_state.asm`
- scheduler initialization in `kernel/debug.asm`
- scheduler-related includes and imports

### Timer

- `kernel/timer.asm`
- timer-related state in `kernel/shared_state.asm`
- timer initialization in `kernel/debug.asm`
- timer wake-up interaction with the scheduler

### Pipe

- `kernel/pipe.asm`
- pipe-related state and diagnostics
- pipe read/write blocking paths
- pipe creation and endpoint-close paths

### Filesystem

- `kernel/ksys_fs.asm`
- `kernel/rp_fs_io.asm`
- filesystem-related state
- FILE_IO gate paths
- RP request/completion paths

## Classification

Classify every suspected debug item as:

| Classification | Meaning | Action |
|---|---|---|
| Correctness state | Used by runtime decisions | Keep |
| Monitor-required state | Read by the current monitor | Keep unless separately approved |
| Boot diagnostic | Used by startup diagnostics | Keep |
| Debug snapshot | Duplicate copy used only for inspection | Remove |
| Debug marker | Indicates which path executed | Remove |
| Debug counter | Used only for tracing/statistics | Remove |
| Obsolete | No current reader or writer | Remove |
| Uncertain | Purpose not proven | Keep temporarily |

## Required output

Create a table containing:

- symbol;
- defining file;
- importing files;
- write sites;
- read sites;
- classification;
- proposed action.

No symbol is removed before this inventory is complete.

---

# Step 2 — Remove scheduler debug instrumentation

## Priority

Scheduler debugging is removed first because it is distributed through frequently executed context-switch and IRQ paths.

## Candidate categories

Remove diagnostic-only:

- scheduler path markers;
- current-PID snapshots;
- selected-PID snapshots;
- saved-SP snapshots;
- loaded-SP snapshots;
- resume-mode snapshots;
- resume-context snapshots;
- old/new process-state snapshots;
- IRQ skip-reason snapshots;
- preemption trace counters.

Potential candidate symbols include:

- `sched_debug_marker`
- `sched_debug_pid`
- `sched_debug_old_pid`
- `sched_debug_old_state`
- `sched_debug_state_pid`
- `sched_debug_state_old`
- `sched_debug_state_new`
- `dbg_sched_path`
- `dbg_sched_current_pid`
- `dbg_sched_selected_pid`
- `dbg_sched_saved_pid`
- `dbg_sched_saved_sp`
- `dbg_sched_saved_mode`
- `dbg_sched_loaded_pid`
- `dbg_sched_loaded_sp`
- `dbg_sched_resume_mode`
- `dbg_sched_resume_pid`
- `dbg_sched_resume_context`
- `dbg_irq_preempt_count`
- `dbg_irq_current_pid`
- `dbg_irq_selected_pid`
- `dbg_irq_saved_sp`
- `dbg_irq_loaded_sp`
- `dbg_irq_skip_reason`

These names are candidates only. Each must be checked against actual reads before removal.

## Removal procedure

1. Remove one diagnostic block at a time.
2. Verify that no branch depends on the stored value.
3. Verify register liveness after removal:
   - A;
   - X;
   - Y;
   - carry;
   - interrupt state.
4. Preserve all actual:
   - process-state changes;
   - stack saves;
   - stack restores;
   - context changes;
   - scheduler-lock operations;
   - wake-up logic.
5. Remove unused imports after code deletion.
6. Remove shared storage only after all references are gone.

## Validation

After each scheduler cleanup group:

- boot;
- timer IRQ;
- repeated preemption;
- voluntary yield;
- block/wake;
- first process start;
- resumed process execution;
- idle-to-runnable transition;
- process exit during scheduling;
- stack integrity.

Record ROM and BSS changes.

---

# Step 3 — Remove timer debug instrumentation

## Scope

Inspect timer code for diagnostic-only:

- PID snapshots;
- selected timer-slot snapshots;
- current-time snapshots;
- expiry-time snapshots;
- wake-scan markers;
- timer-path markers;
- trace counters.

Potential candidate symbols include:

- `dbg_timer_pid`
- `dbg_timer_slot`
- `dbg_timer_until_lo`
- `dbg_timer_until_hi`
- `dbg_timer_now_lo`
- `dbg_timer_now_hi`

## Preserve

Do not remove:

- real system tick state;
- active timer slots;
- timer expiration values;
- PID ownership required for wake-up;
- wait reason/object;
- scheduler interaction needed to wake a process;
- IRQ acknowledgement and timer-source handling.

## Removal procedure

1. Determine whether each value is a duplicate debug copy or actual timer state.
2. Remove only duplicate copies and path markers.
3. Remove unused initialization.
4. Remove unused imports/exports.
5. Remove associated BSS only after no references remain.

## Validation

- timer tick progression;
- one sleeping process;
- multiple sleeping processes;
- different wake-up times;
- timer-slot reuse;
- timer cancellation where implemented;
- idle-to-runnable transition;
- repeated sleep/wake loops.

Record ROM and BSS changes.

---

# Step 4 — Remove pipe debug instrumentation

## Scope

Inspect pipe code for diagnostic-only:

- pipe-index snapshots;
- read/write position snapshots;
- reader/writer count copies;
- wait-path markers;
- EOF-path markers;
- broken-pipe markers;
- creation-stage markers;
- endpoint-close markers;
- temporary test counters.

## Preserve

Do not remove actual:

- pipe allocation state;
- ring-buffer head/tail/count;
- reader count;
- writer count;
- read wait state;
- write wait state;
- EOF detection;
- broken-pipe detection;
- wake-up calls;
- FD/open-object references;
- process ownership needed for cleanup.

## Removal procedure

1. Identify every debug write in:
   - pipe creation;
   - pipe read;
   - pipe write;
   - endpoint close;
   - process cleanup.
2. Prove that the value is not subsequently used.
3. Remove diagnostic-only stores and associated initialization.
4. Remove stale imports/exports.
5. Remove shared-state fields only after all references are gone.

## Validation

- basic pipe creation;
- read/write;
- empty-pipe read blocking;
- full-pipe write blocking;
- reader wake-up;
- writer wake-up;
- EOF after final writer closes;
- broken pipe after final reader closes;
- inherited pipe endpoints;
- process exit while owning pipe endpoints;
- process termination while blocked.

Record ROM and BSS changes.

---

# Step 5 — Remove filesystem debug instrumentation

## Scope

Inspect:

- `kernel/ksys_fs.asm`
- `kernel/rp_fs_io.asm`
- FILE_IO gate use
- RP request/completion code

Remove diagnostic-only:

- operation-stage markers;
- request snapshots;
- result snapshots;
- path-progress markers;
- RP status copies;
- temporary error snapshots;
- wait-path markers;
- duplicate PID/FD/path-pointer copies used only for inspection.

## Preserve

Do not remove:

- syscall argument state required across blocking;
- FILE_IO gate ownership;
- RP request state;
- RP completion state;
- path buffers required by current implementation;
- file descriptor state;
- result values returned to user space;
- error codes;
- process wait reason/object;
- cleanup paths.

## Removal procedure

1. Trace every debug field through request setup, blocking, completion, and return.
2. Distinguish required continuation state from inspection-only snapshots.
3. Remove operation markers and duplicate copies only.
4. Remove stale initialization.
5. Remove unused imports/exports.
6. Remove storage after all references are gone.

## Validation

- open;
- close;
- read;
- write;
- seek;
- tell;
- delete;
- rename;
- mkdir;
- rmdir;
- opendir;
- readdir;
- chdir;
- getcwd;
- invalid path;
- RP error return;
- simultaneous filesystem callers;
- FILE_IO gate blocking/wake-up.

Record ROM and BSS changes.

---

# Step 6 — Remove obsolete debug initialization

## Scope

Inspect `kernel/debug.asm` after scheduler, timer, pipe, and filesystem cleanup.

## Actions

1. Remove initialization for every deleted debug field.
2. Remove stale imports and exports.
3. Remove deleted fields from `kernel/shared_state.asm`.
4. If `debug_init` no longer initializes required data:
   - remove its call from kernel startup;
   - remove its import;
   - remove `kernel/debug.asm` from the kernel source list.
5. If a small amount of required diagnostic initialization remains:
   - move it to the owning subsystem;
   - remove the generic debug module.

## Validation

- clean build;
- boot;
- scheduler;
- timer;
- pipe;
- filesystem;
- monitor entry/exit;
- no uninitialized correctness state.

---

# Step 7 — Dead-symbol cleanup

After all selected diagnostics are removed:

1. remove stale `.import` declarations;
2. remove stale `.export` declarations;
3. remove unused includes;
4. remove unused constants;
5. remove unused zero-page fields;
6. remove unused BSS fields;
7. remove empty or obsolete modules from the build;
8. perform a clean rebuild;
9. verify that `out/` was not modified manually.

`klog` remains linked.

---

# Step 8 — Full regression

Repeat the established functional validation for the currently implemented system:

- boot;
- timer IRQ;
- preemptive scheduling;
- context switching;
- process blocking and wake-up;
- console input/output;
- monitor enter/exit;
- scheduler lock behavior;
- FILE_IO gate behavior;
- RP request serialization;
- timer sleep/wake;
- pipe blocking and wake-up;
- pipe EOF;
- broken pipe;
- filesystem smoke tests;
- process creation;
- process exit;
- zombie handling;
- wait handling;
- currently implemented signal behavior.

No `^C` test is included because `^C` processing is not implemented yet.

---

# Step 9 — Phase 1 size report

Produce:

| Item | Before | After | Difference |
|---|---:|---:|---:|
| Kernel binary | | | |
| `KERN_TEXT` | | | |
| `KERNEL_ENTRY` | | | |
| Kernel BSS | | | |
| Zero page | | | |
| `scheduler.o` | | | |
| `timer.o` | | | |
| `pipe.o` | | | |
| `ksys_fs.o` | | | |
| `rp_fs_io.o` | | | |
| `shared_state.o` | | | |
| `debug.o` | | | |

Also document:

- every removed debug symbol;
- every retained debug-looking symbol;
- the reason each retained symbol remains;
- exact ROM saving;
- exact BSS saving;
- exact zero-page saving.

---

# Acceptance criteria

Phase 1 is complete when:

1. superfluous debugging code/data is removed from scheduler, timer, pipe, and filesystem;
2. all removed fields are proven non-functional;
3. scheduler and IRQ semantics remain unchanged;
4. timer wake-up behavior remains unchanged;
5. pipe blocking and lifetime behavior remain unchanged;
6. filesystem blocking and completion behavior remain unchanged;
7. stale initialization, imports, exports, and storage are removed;
8. `klog` remains available;
9. all current regression tests pass;
10. exact size savings are recorded;
11. the result becomes the validated baseline for Phase 2.

---

# Exclusions

Do not perform these changes in Phase 1:

- filesystem transport redesign;
- path-resolution relocation to RP2350;
- CWD-handle redesign;
- spawn redesign;
- FD architecture redesign;
- pipe architecture redesign;
- blocking-I/O continuation redesign;
- scheduler consolidation;
- syscall ABI changes;
- unrelated instruction-level optimization.

---

# Version sequence

| Version | Change |
|---|---|
| P1.1 | Size baseline and debug inventory |
| P1.2 | Scheduler debug removal |
| P1.3 | Timer debug removal |
| P1.4 | Pipe debug removal |
| P1.5 | Filesystem debug removal |
| P1.6 | Remove obsolete debug initialization and storage |
| P1.7 | Dead-symbol cleanup |
| P1.8 | Full regression and final size report |

Each version must build, boot, and pass the tests relevant to the changed subsystem.
