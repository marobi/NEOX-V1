# NEOX / NEO6502_MMU Documentation

This documentation describes the NEOX software model and the RP-side hardware/backend model. It is intentionally not tied to a specific source ZIP or software version. Version and build identifiers belong in release notes or validation logs, not in the architectural documentation.

## Documentation map

```text
README.md

docs/
  architecture.md
  libneox_cc65.md
  validation.md
  user_tasks.md

  interface/
    mailbox_abi.md

  6502_kernel/
    process_management.md
    scheduler_and_timers.md
    spawn_and_exec.md
    signalling.md
    pipes.md
    filesystem_model.md
    syscall_abi.md

  shell/
    neosh_nbox_applets.md
    command_execution_modes.md

  rp_side/
    rp_overview.md
    usb_subsystem.md
    keyboard_locale.md
    vdu_subsystem.md
    keyboard_and_input.md
    vdu_mouse_support.md
    console_focus_selection.md
    onscreen_editing.md
    mailbox_bridge.md
    6502_control_and_debug.md
    6502_clock_and_irq_generation.md
    transparent_memory_access.md

  monitor/
    micmon_monitor.md
    6502_micmon_monitor.md
```

## System split

NEOX is split into four major documentation domains:

1. **6502 kernel**: process state, scheduler-visible state, file descriptors, pipes, signals, syscalls, spawn, wait/reap, cwd and filesystem semantics.
2. **Shell/app layer**: `neosh`, `nbox`, resident applets, command execution policy.
3. **RP side**: USB host, keyboard/mouse, VDU, transparent line editing, mailbox dispatcher, hardware control, 6502 clock generation, IRQ generation, transparent memory access.
4. **Monitor/debug layer**: RP-side MicMon/control monitor, 6502 MicMon machine monitor, debugger/disassembler facilities, memory/MMU/CPU control commands, and diagnostic commands.

## Current command set

The documented shell command set is:

```text
PWD CD LS CAT ECHO RM MV MKDIR RMDIR CP PS KILL
```

Diagnostic spawn test applets are intentionally omitted from normal documentation. The spawn/wait infrastructure remains part of the system architecture.

## Build/version rule

Build numbers and generated ZIP names are release artifacts. Do not hard-code those identifiers into architectural documents. Record them in validation notes only when comparing specific builds.


## Build 128 address-map migration

The BIOS remains at `$F000-$F0FF`; the public syscall cartridge remains separate at `$F100-$F1FF`.

- `docs/user_tasks.md`: boot-task roles, diagnostics, Task 5 disable state, and Task 6 shell bootstrap.
