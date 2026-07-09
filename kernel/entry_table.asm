; ============================================================
; entry_table.asm
; NEOX - fixed kernel entry table
;
; Purpose:
;   Provides stable entry points at the start of the kernel
;   image for other images (syscall layer, BIOS, etc.).
;
; Layout:
;   - Located at KERNEL_BASE ($8000)
;   - Reserved kernel-entry area is $0100 bytes.
;
; Notes:
;   Padding ensures that KERN_TEXT always starts at $8100.
; ============================================================

.setcpu "65C02"

.include "kernel.inc"

.export kernel_entry_table

.import kernel_main
.import set_brk_vector
.import enter_monitor
.import leave_monitor
.import ksys_read
.import ksys_write
.import ksys_exit
.import ksys_yield
.import ksys_sleep
.import ksys_close
.import ksys_dup
.import ksys_dup2
.import ksys_pipe
.import pipe_create_between_fd
.import ksys_ticks
.import ksys_signal
.import ksys_open
.import ksys_load_file_to_memory
.import ksys_save_memory_to_file
.import ksys_seek
.import ksys_tell
.import ksys_delete
.import ksys_rename
.import ksys_opendir
.import ksys_readdir
.import ksys_closedir
.import ksys_chdir
.import ksys_getcwd
.import ksys_mkdir
.import ksys_rmdir
.import ksys_getprocinfo
.import ksys_spawn_alloc_resident
.import ksys_spawn_fd_inherit
.import ksys_spawn_fd_dup_child
.import ksys_spawn_fd_close
.import ksys_spawn_commit
.import ksys_spawn_abort
.import ksys_waitpid
.import ksys_spawn_set_launch_id
.import ksys_get_launch_id
.import ksys_spawn_set_args2
.import ksys_get_launch_args2

.segment "KERNEL_ENTRY"

.assert * = KERNEL_BASE, error, "KERNEL_ENTRY must start at KERNEL_BASE"

RESET:
kernel_entry_table:
    jmp kernel_main
    jmp enter_monitor
	jmp set_brk_vector
	jmp leave_monitor
	jmp ksys_read
	jmp ksys_write
	jmp ksys_exit
	jmp ksys_yield
	jmp ksys_sleep
	jmp ksys_close
	jmp ksys_dup
	jmp ksys_dup2
	jmp ksys_pipe
	jmp pipe_create_between_fd
	jmp ksys_ticks
	jmp ksys_signal
    jmp ksys_open
    jmp ksys_load_file_to_memory
    jmp ksys_save_memory_to_file
    jmp ksys_seek
    jmp ksys_tell
    jmp ksys_delete
    jmp ksys_rename
    jmp ksys_opendir
    jmp ksys_readdir
    jmp ksys_closedir
    jmp ksys_chdir
    jmp ksys_getcwd
    jmp ksys_mkdir
    jmp ksys_rmdir
    jmp ksys_getprocinfo
    jmp ksys_spawn_alloc_resident
    jmp ksys_spawn_fd_inherit
    jmp ksys_spawn_fd_dup_child
    jmp ksys_spawn_fd_close
    jmp ksys_spawn_commit
    jmp ksys_spawn_abort
    jmp ksys_waitpid
    jmp ksys_spawn_set_launch_id
    jmp ksys_get_launch_id
    jmp ksys_spawn_set_args2
    jmp ksys_get_launch_args2

; KERNEL_ENTRY area is $0100 bytes.
; Current table: 42 absolute JMP entries * 3 bytes = $7E bytes.
; Remaining fixed padding: $0100 - $7E = $82 bytes.
; Keep this explicit because ca65 cannot use relocatable PC (*)
; in the .res count expression here.
KERNEL_ENTRY_COUNT         = 42
KERNEL_ENTRY_RESERVED_SIZE = $0100
KERNEL_ENTRY_USED_BYTES    = KERNEL_ENTRY_COUNT * KERNEL_ENTRY_SIZE

    .assert KERNEL_ENTRY_USED_BYTES <= KERNEL_ENTRY_RESERVED_SIZE, error, "KERNEL_ENTRY overflows reserved entry area"
    .res KERNEL_ENTRY_RESERVED_SIZE - KERNEL_ENTRY_USED_BYTES, $00
