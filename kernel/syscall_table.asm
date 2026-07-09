; ============================================================
; syscall_table.asm
; NEOX - syscall jump table and kernel-side syscall handlers
;
; Purpose:
;   Defines the fixed syscall jump table in shared syscall page C
;   and implements the kernel-side handlers for currently
;   supported syscalls.
;
; Design:
;   - Syscall stubs live at SYSCALL_BASE ($C000)
;   - Each entry is a 3-byte JMP
;   - User code calls fixed entry addresses
;   - Handlers run in shared syscall code
;
; I/O pointer policy:
;   - io_ptr is used by the syscall/RP console path
;   - read/write fully decode the argument block first
;   - only after that is io_ptr repointed to the caller buffer
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "kernel.inc"

.export syscall_table
.export k_exit
.export k_open
.export k_close
.export k_read
.export k_write
.export k_monitor
.export k_load_file_to_memory
.export k_save_memory_to_file
.export k_seek
.export k_tell
.export k_delete
.export k_rename
.export k_pipe
.export k_yield
.export k_sleep
.export k_dup
.export k_dup2
.export k_ticks
.export k_signal
.export k_opendir
.export k_readdir
.export k_closedir
.export k_chdir
.export k_getcwd
.export k_mkdir
.export k_rmdir
.export k_getprocinfo
.export k_spawn_alloc_resident
.export k_spawn_fd_inherit
.export k_spawn_fd_dup_child
.export k_spawn_fd_close
.export k_spawn_commit
.export k_spawn_abort
.export k_waitpid
.export k_spawn_set_launch_id
.export k_get_launch_id
.export k_spawn_set_args2
.export k_get_launch_args2

.segment "SYSCALL_STUBS"

.assert * = SYSCALL_BASE, error, "SYSCALL_STUBS must start at SYSCALL_BASE"

; ------------------------------------------------------------
; syscall_table
;
; Entry index must match syscall number exactly:
;   0  -> k_exit
;   1  -> k_open
;   2  -> k_close
;   3  -> k_read
;   4  -> k_write
;   5  -> k_monitor
;   6  -> k_load_file_to_memory
;   7  -> k_save_memory_to_file
;   8  -> k_seek
;   9  -> k_tell
;   10 -> k_pipe
;   11 -> k_yield
;   12 -> k_delete
;   13 -> k_rename
;	14 -> k_sleep
;	15 -> k_dup
;	16 -> k_dup2
;   17 -> k_ticks
;   18 -> k_signal
;   19 -> k_opendir
;   20 -> k_readdir
;   21 -> k_closedir
;   22 -> k_chdir
;   23 -> k_getcwd
;   24 -> k_mkdir
;   25 -> k_rmdir
;   26 -> k_getprocinfo
;   27 -> k_spawn_alloc_resident
;   28 -> k_spawn_fd_inherit
;   29 -> k_spawn_fd_dup_child
;   30 -> k_spawn_fd_close
;   31 -> k_spawn_commit
;   32 -> k_spawn_abort
;   33 -> k_waitpid
;   34 -> k_spawn_set_launch_id
;   35 -> k_get_launch_id
;   36 -> k_spawn_set_args2
;   37 -> k_get_launch_args2
; ------------------------------------------------------------

syscall_table:
    jmp k_exit
    jmp k_open
    jmp k_close
    jmp k_read
    jmp k_write
    jmp k_monitor
    jmp k_load_file_to_memory
    jmp k_save_memory_to_file
    jmp k_seek
    jmp k_tell
    jmp k_pipe
    jmp k_yield
    jmp k_delete
    jmp k_rename
	jmp k_sleep
    jmp k_dup
    jmp k_dup2
	jmp k_ticks
	jmp k_signal
    jmp k_opendir
    jmp k_readdir
    jmp k_closedir
    jmp k_chdir
    jmp k_getcwd
    jmp k_mkdir
    jmp k_rmdir
    jmp k_getprocinfo
    jmp k_spawn_alloc_resident
    jmp k_spawn_fd_inherit
    jmp k_spawn_fd_dup_child
    jmp k_spawn_fd_close
    jmp k_spawn_commit
    jmp k_spawn_abort
    jmp k_waitpid
    jmp k_spawn_set_launch_id
    jmp k_get_launch_id
    jmp k_spawn_set_args2
    jmp k_get_launch_args2

.segment "KERN_TEXT"

; ------------------------------------------------------------
; sys_ok_ax0
;
; Return:
;   C clear
;   A = 0
;   X = 0
; ------------------------------------------------------------

.proc sys_ok_ax0
    lda #0
    tax
    clc
    rts
.endproc


.proc k_exit
    jmp KERN_ENTRY_KSYS_EXIT
.endproc

.proc k_open
    jmp KERN_ENTRY_KSYS_OPEN
.endproc

.proc k_close
    jmp KERN_ENTRY_KSYS_CLOSE
.endproc

.proc k_read
	jmp KERN_ENTRY_KSYS_READ
.endproc

.proc k_write
	jmp KERN_ENTRY_KSYS_WRITE
.endproc

.proc k_monitor
    jmp KERN_ENTRY_MONITOR
.endproc

.proc k_load_file_to_memory
    jmp KERN_ENTRY_KSYS_LOAD_FILE_TO_MEMORY
.endproc

.proc k_save_memory_to_file
    jmp KERN_ENTRY_KSYS_SAVE_MEMORY_TO_FILE
.endproc

.proc k_seek
    jmp KERN_ENTRY_KSYS_SEEK
.endproc

.proc k_tell
    jmp KERN_ENTRY_KSYS_TELL
.endproc

.proc k_pipe
    jmp KERN_ENTRY_KSYS_PIPE
.endproc

.proc k_yield
    ; Enter cooperative scheduler path with IRQs disabled.
    ;
    ; This closes the race where a timer IRQ arrives after the
    ; user has entered sys_yield but before sched_yield executes
    ; its own SEI.
    sei

    jsr KERN_ENTRY_KSYS_YIELD

    clc
    rts
.endproc

.proc k_delete
    jmp KERN_ENTRY_KSYS_DELETE
.endproc

.proc k_rename
    jmp KERN_ENTRY_KSYS_RENAME
.endproc

.proc k_sleep
	jmp KERN_ENTRY_KSYS_SLEEP
.endproc

.proc k_dup
    jmp KERN_ENTRY_KSYS_DUP
.endproc

.proc k_dup2
    jmp KERN_ENTRY_KSYS_DUP2
.endproc

.proc k_ticks
    jmp KERN_ENTRY_KSYS_TICKS
.endproc

.proc k_signal
    jmp KERN_ENTRY_KSYS_SIGNAL
.endproc

.proc k_opendir
    jmp KERN_ENTRY_KSYS_OPENDIR
.endproc

.proc k_readdir
    jmp KERN_ENTRY_KSYS_READDIR
.endproc

.proc k_closedir
    jmp KERN_ENTRY_KSYS_CLOSEDIR
.endproc

.proc k_chdir
    jmp KERN_ENTRY_KSYS_CHDIR
.endproc

.proc k_getcwd
    jmp KERN_ENTRY_KSYS_GETCWD
.endproc

.proc k_mkdir
    jmp KERN_ENTRY_KSYS_MKDIR
.endproc

.proc k_rmdir
    jmp KERN_ENTRY_KSYS_RMDIR
.endproc

.proc k_getprocinfo
    jmp KERN_ENTRY_KSYS_GETPROCINFO
.endproc


.proc k_spawn_alloc_resident
    jmp KERN_ENTRY_KSYS_SPAWN_ALLOC_RESIDENT
.endproc

.proc k_spawn_fd_inherit
    jmp KERN_ENTRY_KSYS_SPAWN_FD_INHERIT
.endproc

.proc k_spawn_fd_dup_child
    jmp KERN_ENTRY_KSYS_SPAWN_FD_DUP_CHILD
.endproc

.proc k_spawn_fd_close
    jmp KERN_ENTRY_KSYS_SPAWN_FD_CLOSE
.endproc

.proc k_spawn_commit
    jmp KERN_ENTRY_KSYS_SPAWN_COMMIT
.endproc

.proc k_spawn_abort
    jmp KERN_ENTRY_KSYS_SPAWN_ABORT
.endproc
.proc k_waitpid
    jmp KERN_ENTRY_KSYS_WAITPID
.endproc

.proc k_spawn_set_launch_id
    jmp KERN_ENTRY_KSYS_SPAWN_SET_LAUNCH_ID
.endproc

.proc k_get_launch_id
    jmp KERN_ENTRY_KSYS_GET_LAUNCH_ID
.endproc

.proc k_spawn_set_args2
    jmp KERN_ENTRY_KSYS_SPAWN_SET_ARGS2
.endproc

.proc k_get_launch_args2
    jmp KERN_ENTRY_KSYS_GET_LAUNCH_ARGS2
.endproc

