# NEOX

NEOX is a minimalistic UNIX-like operating system for the **NEO6502-MMU system**.

The goal of NEOX is to provide a small, inspectable, and deterministic environment with support for multitasking on a 6502-based platform.

---

## Platform: NEO6502-MMU

NEOX runs on a heterogeneous system consisting of:

* **W65C02 CPU**
* **RP2350 supervisor**

The RP2350 is responsible for:

* MMU context switching
* device and I/O handling
* mailbox-based service interface

The 6502 executes all kernel and user code.

---

## Design goals

NEOX aims to be:

* minimalistic and fully inspectable
* deterministic and explicit in all operations
* UNIX-like in structure (not necessarily implementation)
* free of hidden runtime dependencies

---

## Architecture

### Execution model

* Kernel and user tasks run on the 6502
* RP2350 provides external services
* All I/O is performed via a mailbox protocol
* Scheduling is driven by a **timer IRQ**

---

## MMU and Context Model

The system uses **multiple execution contexts**.

### Context roles

* **Context 0**

  * supervisor / kernel control
  * used for MICMON and system inspection
  * **not part of the scheduler**

* **Contexts 1..N**

  * runnable processes
  * scheduled by the kernel

---

### Memory layout (logical)

| Page | Type    | Description           |
| ---- | ------- | --------------------- |
| 0–7  | Private | RAM (ZP, stack, heap) |
| 8–A  | Shared  | general shared RAM    |
| B    | Shared  | MICMON                |
| C    | Shared  | Syscalls              |
| D    | Shared  | RP2350 I/O            |
| E    | Shared  | Kernel                |
| F    | Shared  | BIOS                  |

Important:

* **Zero page and stack are private per context**
* Shared state must live in pages `8+`

---

## Scheduler

NEOX implements a **timer-driven preemptive scheduler**.

### Key properties

* Round-robin scheduling
* IRQ-driven context switching
* Context 0 is supervisor-only and excluded from normal scheduling
* MMU switching is a mapping primitive only
* Context switching policy is handled entirely in kernel code

---

### Process lifecycle

Processes move through these states:

```text
EMPTY → NEW → RUNNING ↔ READY
```

---

### First run vs normal run

NEOX distinguishes between:

#### First run (bootstrap)

* Process is in `PROC_NEW`
* Scheduler:

  * switches MMU context
  * jumps to bootstrap entry
* Bootstrap:

  * initializes the private stack
  * jumps to the process entry point

#### Subsequent runs

* Stack pointer is saved on IRQ
* Scheduler restores SP
* Execution resumes via `RTI`

---

## Interrupt model

* Timer IRQ is the scheduler trigger
* IRQ entry:

  * saves A/X/Y
  * acknowledges or classifies the IRQ source
  * checks scheduler lock
  * either:

    * restores the interrupted context unchanged
    * or performs context switch

Context switching itself happens only in the scheduler path.

---

## Preemption control

NEOX uses a minimal preemption guard:

```text
sched_lock
```

* non-zero → scheduler is disabled
* used during short critical kernel operations
* **not a general mutex**

This prevents timer-driven preemption during operations such as mailbox exchange or scheduler table updates.

---

## Mailbox protocol

All I/O is delegated to the RP2350.

### Request flow

1. Kernel fills shared request block
2. Sets `RP_STATUS = BUSY`
3. Writes command to doorbell register
4. RP2350 processes request
5. RP2350 sets `DONE` or `ERROR`

---

### Mailbox layout (shared RAM)

```text
RP_REQ_BASE = $80C0   (shared page 8)
```

This replaces the earlier low-RAM location, which is no longer valid because low memory is private per context.

---

### Control registers

```text
RP_DOORBELL = $D010
RP_STATUS   = $D011
```

These live in the shared I/O page.

---

### Synchronization

* `rp_lock` → mailbox ownership
* `sched_lock` → prevents preemption during transactions

---

## Syscall interface

```text
SYSCALL_BASE = $C000
ENTRY SIZE   = 3 bytes (JMP)
```

### Current syscalls

| ID | Name  | Description    |
| -- | ----- | -------------- |
| 3  | read  | console input  |
| 4  | write | console output |

### Calling convention

* `X/Y` → pointer to argument block
* `C` clear → success
* `C` set → error (`Y = errno`)
* `A/X` → return value

---

## Current status

* MMU context model implemented
* shared vs private memory model defined and applied
* timer-driven scheduler implemented
* first-run bootstrap model implemented
* supervisor context 0 model implemented
* mailbox I/O operational
* console read/write working
* MICMON retained as supervisor/debug environment

---

## Project structure

* `kernel/` → kernel (scheduler, MMU, IRQ, RP interface)
* `user/` → test tasks and user-side support code
* `include/` → ABI and shared definitions
* `build/` → linker configs and helper tools
* RP2350 firmware → hardware abstraction / MMU / I/O controller

---

## Build

```bash
make
```

---

## Notes

NEOX is still in an early but functional stage.

Current focus:

* validating scheduler stability
* refining context switching
* keeping supervisor/debug access through context 0
* expanding the syscall layer

Planned next steps:

* blocking syscalls
* process control
* basic userland environment
* filesystem abstraction

---

## License

TBD
