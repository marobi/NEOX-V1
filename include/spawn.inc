; ============================================================
; spawn.inc
; NEOX - parent-controlled resident spawn setup ABI
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
; spawn_alloc_resident_args
;
; The caller supplies a resident entry address in the already
; preloaded user image.  The kernel allocates a PID/context pair,
; records the caller as parent, leaves the child in PROC_SETUP,
; and writes the child PID into result_pid.
; ------------------------------------------------------------

.struct spawn_alloc_resident_args
    entry           .word
    flags           .byte
    result_pid      .byte
.endstruct

SPAWN_ALLOC_RESIDENT_ARGS_SIZE = .sizeof(spawn_alloc_resident_args)


; ------------------------------------------------------------
; spawn_set_launch_id_args
;
; Assign one generic launch selector byte to a pending child.
; The kernel stores this per child PID. The resident child entry
; later reads it through SYS_GET_LAUNCH_ID. The value semantics are
; userland-defined; for nbox children it is an NBOX_APPLET_* id.
; ------------------------------------------------------------

.struct spawn_set_launch_id_args
    child_pid       .byte
    launch_id       .byte
.endstruct

SPAWN_SET_LAUNCH_ID_ARGS_SIZE = .sizeof(spawn_set_launch_id_args)

; ------------------------------------------------------------
; spawn_set_args2_args
;
; Assign up to two launch arguments to a pending child. The kernel
; copies argument bytes from the active parent context into shared
; per-process launch storage. Lengths exclude the trailing NUL.
; ------------------------------------------------------------

.struct spawn_set_args2_args
    child_pid       .byte
    argc            .byte
    arg0_ptr        .word
    arg0_len        .byte
    arg1_ptr        .word
    arg1_len        .byte
.endstruct

SPAWN_SET_ARGS2_ARGS_SIZE = .sizeof(spawn_set_args2_args)

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

; ------------------------------------------------------------
; spawn_fd_inherit_args
;
; Clone one fd from the active parent into the pending child.
; ------------------------------------------------------------

.struct spawn_fd_inherit_args
    child_pid       .byte
    parent_fd       .byte
    child_fd        .byte
.endstruct

SPAWN_FD_INHERIT_ARGS_SIZE = .sizeof(spawn_fd_inherit_args)

; ------------------------------------------------------------
; spawn_fd_dup_child_args
;
; Duplicate one existing child fd to another child fd.
; This is the child-side equivalent of dup2(source_fd, target_fd)
; while the child is still in PROC_SETUP.
; ------------------------------------------------------------

.struct spawn_fd_dup_child_args
    child_pid       .byte
    source_fd       .byte
    target_fd       .byte
.endstruct

SPAWN_FD_DUP_CHILD_ARGS_SIZE = .sizeof(spawn_fd_dup_child_args)

; ------------------------------------------------------------
; spawn_fd_close_args
;
; Close one fd in the pending child.  Closing an already closed fd
; is treated as success by the spawn setup ABI.
; ------------------------------------------------------------

.struct spawn_fd_close_args
    child_pid       .byte
    child_fd        .byte
.endstruct

SPAWN_FD_CLOSE_ARGS_SIZE = .sizeof(spawn_fd_close_args)

; ------------------------------------------------------------
; spawn_child_args
;
; Used by commit/abort operations.
; ------------------------------------------------------------

.struct spawn_child_args
    child_pid       .byte
.endstruct

SPAWN_CHILD_ARGS_SIZE = .sizeof(spawn_child_args)

.endif
