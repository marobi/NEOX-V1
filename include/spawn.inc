; ============================================================
; spawn.inc
; NEOX - unified resident spawn ABI
; ============================================================

.ifndef __SPAWN_INC__
__SPAWN_INC__ = 1

.include "config.inc"
.include "process.inc"

SPAWN_FLAGS_NONE = PROC_FLAG_NONE
SPAWN_FLAGS_VALID = PROC_FLAGS_CREATE_MASK
SPAWN_LAUNCH_NONE = $FF
SPAWN_FD_CLOSED = $FF

; Maximum process-private launch-line storage including its terminating NUL.
; The public length excludes the NUL and must be less than SPAWN_LINE_MAX.
SPAWN_LINE_MAX = 64

; ------------------------------------------------------------
; spawn_resident_args
;
; The parent transfers one opaque argument line to the child. The kernel
; does not tokenize, count, quote, or otherwise interpret argument bytes.
; arg_line_len excludes the terminating NUL.
; ------------------------------------------------------------
.struct spawn_resident_args
    entry           .word
    launch_id       .byte
    arg_line_ptr    .word
    arg_line_len    .byte
    stdin_fd        .byte
    stdout_fd       .byte
    stderr_fd       .byte
    flags           .byte   ; initial child proc_flags
    result_pid      .byte
.endstruct

SPAWN_RESIDENT_ARGS_SIZE = .sizeof(spawn_resident_args)

; ------------------------------------------------------------
; spawn_get_line_args
;
; Child-side retrieval of the opaque launch argument line.
; buffer_size includes space for the terminating NUL.
; result_len excludes the terminating NUL.
; ------------------------------------------------------------
.struct spawn_get_line_args
    buffer_ptr      .word
    buffer_size     .byte
    result_len      .byte
.endstruct

SPAWN_GET_LINE_ARGS_SIZE = .sizeof(spawn_get_line_args)

.endif
