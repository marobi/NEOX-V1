; ============================================================
; spawn.inc
; NEOX - parent-controlled resident spawn setup ABI
; ============================================================

.ifndef __SPAWN_INC__
__SPAWN_INC__ = 1

; ------------------------------------------------------------
; Spawn allocation flags
; ------------------------------------------------------------

SPAWN_FLAGS_NONE = $00

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
