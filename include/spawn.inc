; ============================================================
; spawn.inc
; NEOX - unified resident spawn ABI
; ============================================================

.ifndef __SPAWN_INC__
__SPAWN_INC__ = 1

.include "config.inc"

; ------------------------------------------------------------
; Spawn allocation flags
; ------------------------------------------------------------

SPAWN_FLAGS_NONE = $00

; No launch selector has been assigned to the pending child.
SPAWN_LAUNCH_NONE = $FF

; Resident launch argument slots are intentionally small and fixed.
; Keep this compact because launch state lives in shared kernel RAM.
SPAWN_ARG_MAX = 24


; ------------------------------------------------------------
; spawn_resident_args
;
; Unified resident-image spawn transaction. The kernel allocates the
; child, copies launch metadata, maps parent descriptors into child
; stdin/stdout/stderr, clones cwd, and publishes the child atomically.
;
; A parent fd value of SPAWN_FD_CLOSED leaves that child descriptor
; closed. Argument lengths exclude the trailing NUL.
; ------------------------------------------------------------

SPAWN_FD_CLOSED = $FF

.struct spawn_resident_args
    entry           .word
    launch_id       .byte
    argc            .byte
    arg0_ptr        .word
    arg0_len        .byte
    arg1_ptr        .word
    arg1_len        .byte
    stdin_fd        .byte
    stdout_fd       .byte
    stderr_fd       .byte
    flags           .byte
    result_pid      .byte
.endstruct

SPAWN_RESIDENT_ARGS_SIZE = .sizeof(spawn_resident_args)

; ------------------------------------------------------------
; spawn_get_args2_args
;
; Child-side retrieval of the current process launch arguments. The
; kernel copies shared launch storage into buffers in the active child
; context and writes argc/length result fields.
; ------------------------------------------------------------

.struct spawn_get_args2_args
    arg0_ptr        .word
    arg0_max        .byte
    arg1_ptr        .word
    arg1_max        .byte
    argc_out        .byte
    arg0_len_out    .byte
    arg1_len_out    .byte
.endstruct

SPAWN_GET_ARGS2_ARGS_SIZE = .sizeof(spawn_get_args2_args)

.endif
