; ============================================================
; spawn.asm
; NEOX nbox diagnostic applet: spawn setup/abort test
;
; Purpose:
;   Exercises the parent-controlled resident spawn setup ABI without
;   committing the child.  The parent allocates a PROC_SETUP child,
;   inherits fd 0/1/2 into it, waits for operator inspection, then
;   aborts the setup child and verifies cleanup via monitor/PS.
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_spawn
.export nbox_cmd_spawnc
.export nbox_cmd_spawnw
.export nbox_cmd_spawni
.export nbox_cmd_spawnl
.export nbox_spawntest_child_entry
.export nbox_spawncommit_child_entry
.export nbox_spawnwait_child_entry

.import nbox_child_entry

.segment "USER_DATA"

nbox_spawn_child_pid:
    .byte $FF

nbox_spawn_key_buf:
    .byte 0

nbox_spawn_alloc_args:
    .word nbox_spawntest_child_entry
    .byte SPAWN_FLAGS_NONE
    .byte $FF

nbox_spawn_fd_inherit_args:
    .byte $FF        ; child_pid
    .byte 0          ; parent_fd
    .byte 0          ; child_fd

nbox_spawn_set_launch_args:
    .byte $FF        ; child_pid
    .byte NBOX_APPLET_NONE

nbox_spawn_set_args2_args:
    .byte $FF        ; child_pid
    .byte 0          ; argc
    .word nbox_spawn_arg_dot
    .byte 1          ; arg0_len
    .word nbox_spawn_arg_empty
    .byte 0          ; arg1_len

nbox_spawn_child_args:
    .byte $FF

nbox_spawn_arg_dot:
    .byte ".", 0

nbox_spawn_arg_empty:
    .byte 0

nbox_spawn_read_args:
    .byte STDIN
    .byte 0
    .word nbox_spawn_key_buf
    .word 1

nbox_spawn_msg_start:
    .byte "SPAWN: ALLOC", 13
NBOX_SPAWN_MSG_START_LEN = * - nbox_spawn_msg_start

nbox_spawn_msg_pid:
    .byte "SPAWNC: CHILD PID $"
NBOX_SPAWN_MSG_PID_LEN = * - nbox_spawn_msg_pid

nbox_spawn_msg_wait:
    .byte "SPAWN: INSPECT NOW, PRESS ENTER TO ABORT", 13
NBOX_SPAWN_MSG_WAIT_LEN = * - nbox_spawn_msg_wait

nbox_spawn_msg_abort_ok:
    .byte "SPAWN: ABORT OK", 13
NBOX_SPAWN_MSG_ABORT_OK_LEN = * - nbox_spawn_msg_abort_ok

nbox_spawn_msg_alloc_fail:
    .byte "SPAWN: ALLOC FAIL $"
NBOX_SPAWN_MSG_ALLOC_FAIL_LEN = * - nbox_spawn_msg_alloc_fail

nbox_spawn_msg_fd_fail:
    .byte "SPAWN: FD FAIL $"
NBOX_SPAWN_MSG_FD_FAIL_LEN = * - nbox_spawn_msg_fd_fail

nbox_spawn_msg_abort_fail:
    .byte "SPAWN: ABORT FAIL $"
NBOX_SPAWN_MSG_ABORT_FAIL_LEN = * - nbox_spawn_msg_abort_fail


nbox_spawn_msg_commit_start:
    .byte "SPAWNC: ALLOC", 13
NBOX_SPAWN_MSG_COMMIT_START_LEN = * - nbox_spawn_msg_commit_start

nbox_spawn_msg_commit_pid:
    .byte "SPAWNC: CHILD PID $"
NBOX_SPAWN_MSG_COMMIT_PID_LEN = * - nbox_spawn_msg_commit_pid

nbox_spawn_msg_commit_ok:
    .byte "SPAWNC: COMMIT OK", 13
NBOX_SPAWN_MSG_COMMIT_OK_LEN = * - nbox_spawn_msg_commit_ok

nbox_spawn_msg_commit_fail:
    .byte "SPAWNC: COMMIT FAIL $"
NBOX_SPAWN_MSG_COMMIT_FAIL_LEN = * - nbox_spawn_msg_commit_fail

nbox_spawn_msg_child_run:
    .byte "SPAWNC CHILD RUN", 13
NBOX_SPAWN_MSG_CHILD_RUN_LEN = * - nbox_spawn_msg_child_run


nbox_spawn_msg_wait_start:
    .byte "SPAWNW: ALLOC", 13
NBOX_SPAWN_MSG_WAIT_START_LEN = * - nbox_spawn_msg_wait_start

nbox_spawn_msg_wait_pid:
    .byte "SPAWNW: CHILD PID $"
NBOX_SPAWN_MSG_WAIT_PID_LEN = * - nbox_spawn_msg_wait_pid

nbox_spawn_msg_wait_zombie:
    .byte "SPAWNW: INSPECT ZOMBIE, PRESS ENTER TO WAIT", 13
NBOX_SPAWN_MSG_WAIT_ZOMBIE_LEN = * - nbox_spawn_msg_wait_zombie

nbox_spawn_msg_wait_status:
    .byte "SPAWNW: EXIT $"
NBOX_SPAWN_MSG_WAIT_STATUS_LEN = * - nbox_spawn_msg_wait_status

nbox_spawn_msg_wait_fail:
    .byte "SPAWNW: WAIT FAIL $"
NBOX_SPAWN_MSG_WAIT_FAIL_LEN = * - nbox_spawn_msg_wait_fail

nbox_spawn_msg_wait_child_run:
    .byte "SPAWNW CHILD RUN", 13
NBOX_SPAWN_MSG_WAIT_CHILD_RUN_LEN = * - nbox_spawn_msg_wait_child_run



nbox_spawn_msg_nbox_start:
    .byte "SPAWNI: ALLOC", 13
NBOX_SPAWN_MSG_NBOX_START_LEN = * - nbox_spawn_msg_nbox_start

nbox_spawn_msg_nbox_pid:
    .byte "SPAWNI: CHILD PID $"
NBOX_SPAWN_MSG_NBOX_PID_LEN = * - nbox_spawn_msg_nbox_pid

nbox_spawn_msg_nbox_set_fail:
    .byte "SPAWNI: SET FAIL $"
NBOX_SPAWN_MSG_NBOX_SET_FAIL_LEN = * - nbox_spawn_msg_nbox_set_fail

nbox_spawn_msg_nbox_commit_ok:
    .byte "SPAWNI: COMMIT OK", 13
NBOX_SPAWN_MSG_NBOX_COMMIT_OK_LEN = * - nbox_spawn_msg_nbox_commit_ok

nbox_spawn_msg_nbox_status:
    .byte "SPAWNI: EXIT $"
NBOX_SPAWN_MSG_NBOX_STATUS_LEN = * - nbox_spawn_msg_nbox_status

nbox_spawn_msg_ls_start:
    .byte "SPAWNL: ALLOC", 13
NBOX_SPAWN_MSG_LS_START_LEN = * - nbox_spawn_msg_ls_start

nbox_spawn_msg_ls_pid:
    .byte "SPAWNL: CHILD PID $"
NBOX_SPAWN_MSG_LS_PID_LEN = * - nbox_spawn_msg_ls_pid

nbox_spawn_msg_ls_set_fail:
    .byte "SPAWNL: SET FAIL $"
NBOX_SPAWN_MSG_LS_SET_FAIL_LEN = * - nbox_spawn_msg_ls_set_fail

nbox_spawn_msg_ls_commit_ok:
    .byte "SPAWNL: COMMIT OK", 13
NBOX_SPAWN_MSG_LS_COMMIT_OK_LEN = * - nbox_spawn_msg_ls_commit_ok

nbox_spawn_msg_ls_status:
    .byte "SPAWNL: EXIT $"
NBOX_SPAWN_MSG_LS_STATUS_LEN = * - nbox_spawn_msg_ls_status

nbox_spawn_errno:
    .byte 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; nbox_spawn_print_errno_line
;
; Input:
;   A/X = message pointer
;   Y   = message length
;   nbox_spawn_errno = errno byte
; ------------------------------------------------------------
.proc nbox_spawn_print_errno_line
    jsr nbox_print_msg
    lda nbox_spawn_errno
    jsr nbox_print_hex_byte
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
; nbox_spawn_abort_child
;
; Abort the currently allocated setup child.  This helper is used on
; both the normal path and fd setup failure cleanup path.
;
; Return:
;   C clear = abort succeeded
;   C set   = abort failed, Y = errno
; ------------------------------------------------------------
.proc nbox_spawn_abort_child
    lda nbox_spawn_child_pid
    sta nbox_spawn_child_args + spawn_child_args::child_pid
    SYSCALL nbox_spawn_child_args, sys_spawn_abort
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawn_inherit_one
;
; Input:
;   A = fd number to inherit from the parent into the same child fd.
;
; Return:
;   C clear = success
;   C set   = failure, Y = errno
; ------------------------------------------------------------
.proc nbox_spawn_inherit_one
    sta nbox_spawn_fd_inherit_args + spawn_fd_inherit_args::parent_fd
    sta nbox_spawn_fd_inherit_args + spawn_fd_inherit_args::child_fd

    lda nbox_spawn_child_pid
    sta nbox_spawn_fd_inherit_args + spawn_fd_inherit_args::child_pid

    SYSCALL nbox_spawn_fd_inherit_args, sys_spawn_fd_inherit
    rts
.endproc


; ------------------------------------------------------------
; nbox_spawn_inherit_stdio
;
; Inherit parent fd 0, 1, and 2 into the pending child.
;
; Return:
;   C clear = success
;   C set   = failure, Y = errno
; ------------------------------------------------------------
.proc nbox_spawn_inherit_stdio
    lda #STDIN
    jsr nbox_spawn_inherit_one
    bcs @fail

    lda #STDOUT
    jsr nbox_spawn_inherit_one
    bcs @fail

    lda #STDERR
    jsr nbox_spawn_inherit_one
    bcs @fail

    clc
    rts

@fail:
    sec
    rts
.endproc


; ------------------------------------------------------------
; nbox_spawn_set_launch_help
;
; Assign NBOX_APPLET_HELP as the launch selector for the currently
; allocated pending child.  V38h1i uses HELP because it needs no argv.
;
; Return:
;   C clear = success
;   C set   = failure, Y = errno
; ------------------------------------------------------------
.proc nbox_spawn_set_launch_help
    lda nbox_spawn_child_pid
    sta nbox_spawn_set_launch_args + spawn_set_launch_id_args::child_pid
    lda #NBOX_APPLET_HELP
    sta nbox_spawn_set_launch_args + spawn_set_launch_id_args::launch_id
    SYSCALL nbox_spawn_set_launch_args, sys_spawn_set_launch_id
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawn_set_launch_ls
;
; Assign NBOX_APPLET_LS as the launch selector for the currently
; allocated pending child.
; ------------------------------------------------------------
.proc nbox_spawn_set_launch_ls
    lda nbox_spawn_child_pid
    sta nbox_spawn_set_launch_args + spawn_set_launch_id_args::child_pid
    lda #NBOX_APPLET_LS
    sta nbox_spawn_set_launch_args + spawn_set_launch_id_args::launch_id
    SYSCALL nbox_spawn_set_launch_args, sys_spawn_set_launch_id
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawn_set_args_ls_dot
;
; Assign argc=1, arg0="." for the pending child.
; ------------------------------------------------------------
.proc nbox_spawn_set_args_ls_dot
    lda nbox_spawn_child_pid
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::child_pid
    lda #1
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::argc
    lda #<nbox_spawn_arg_dot
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::arg0_ptr
    lda #>nbox_spawn_arg_dot
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::arg0_ptr + 1
    lda #1
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::arg0_len
    lda #<nbox_spawn_arg_empty
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::arg1_ptr
    lda #>nbox_spawn_arg_empty
    sta nbox_spawn_set_args2_args + spawn_set_args2_args::arg1_ptr + 1
    stz nbox_spawn_set_args2_args + spawn_set_args2_args::arg1_len
    SYSCALL nbox_spawn_set_args2_args, sys_spawn_set_args2
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawn_commit_child
;
; Commit the currently allocated setup child.
;
; Return:
;   C clear = commit succeeded
;   C set   = commit failed, Y = errno
; ------------------------------------------------------------
.proc nbox_spawn_commit_child
    lda nbox_spawn_child_pid
    sta nbox_spawn_child_args + spawn_child_args::child_pid
    SYSCALL nbox_spawn_child_args, sys_spawn_commit
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawn_wait_for_operator
;
; Wait for one input byte so the monitor can inspect the intermediate
; PROC_SETUP state before the child is aborted.
; ------------------------------------------------------------
.proc nbox_spawn_wait_for_operator
    SYSCALL nbox_spawn_read_args, sys_read
    rts
.endproc

; ------------------------------------------------------------
; nbox_spawntest_child_entry
;
; Safety entry for the diagnostic child.  The SPAWN applet never commits
; the child, but this prevents accidental fall-through to arbitrary code
; if a later manual test commits this entry.
; ------------------------------------------------------------
.proc nbox_spawntest_child_entry
    lda #EXIT_OK
    jmp sys_exit
.endproc


; ------------------------------------------------------------
; nbox_spawncommit_child_entry
;
; Fixed diagnostic child entry for SPAWNC.  The parent commits this child
; after setting fd 0/1/2, so the child proves that a committed resident
; setup process can run, write to inherited stdout, and exit.
; ------------------------------------------------------------
.proc nbox_spawncommit_child_entry
    lda #<nbox_spawn_msg_child_run
    ldx #>nbox_spawn_msg_child_run
    ldy #NBOX_SPAWN_MSG_CHILD_RUN_LEN
    jsr nbox_print_msg

    lda #EXIT_OK
    jmp sys_exit
.endproc


; ------------------------------------------------------------
; nbox_spawnwait_child_entry
;
; Fixed diagnostic child entry for SPAWNW.  The parent commits this
; child, yields so it can exit as a waitable zombie, inspects it, then
; calls SYS_WAITPID to reap and retrieve the exit status.
; ------------------------------------------------------------
.proc nbox_spawnwait_child_entry
    lda #<nbox_spawn_msg_wait_child_run
    ldx #>nbox_spawn_msg_wait_child_run
    ldy #NBOX_SPAWN_MSG_WAIT_CHILD_RUN_LEN
    jsr nbox_print_msg

    lda #$2A
    jmp sys_exit
.endproc

; ------------------------------------------------------------
; nbox_cmd_spawn
;
; Diagnostic command:
;   SPAWN
;
; Expected test flow:
;   - allocates a resident setup child
;   - inherits fd 0, 1, 2 into that child
;   - waits for monitor inspection
;   - aborts child and releases context/fds
; ------------------------------------------------------------
.proc nbox_cmd_spawn
    lda #<nbox_spawn_msg_start
    ldx #>nbox_spawn_msg_start
    ldy #NBOX_SPAWN_MSG_START_LEN
    jsr nbox_print_msg

    SYSCALL nbox_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_alloc_fail
    ldx #>nbox_spawn_msg_alloc_fail
    ldy #NBOX_SPAWN_MSG_ALLOC_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@allocated:
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_pid
    ldx #>nbox_spawn_msg_pid
    ldy #NBOX_SPAWN_MSG_PID_LEN
    jsr nbox_print_msg

    lda nbox_spawn_child_pid
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    jsr nbox_spawn_inherit_stdio
    bcs @fd_fail

    lda #<nbox_spawn_msg_wait
    ldx #>nbox_spawn_msg_wait
    ldy #NBOX_SPAWN_MSG_WAIT_LEN
    jsr nbox_print_msg

    jsr nbox_spawn_wait_for_operator

    jsr nbox_spawn_abort_child
    bcc @abort_ok

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_abort_fail
    ldx #>nbox_spawn_msg_abort_fail
    ldy #NBOX_SPAWN_MSG_ABORT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@abort_ok:
    lda #$FF
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_abort_ok
    ldx #>nbox_spawn_msg_abort_ok
    ldy #NBOX_SPAWN_MSG_ABORT_OK_LEN
    jmp nbox_print_msg

@fd_fail:
    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_fd_fail
    ldx #>nbox_spawn_msg_fd_fail
    ldy #NBOX_SPAWN_MSG_FD_FAIL_LEN
    jmp nbox_spawn_print_errno_line
.endproc

; ------------------------------------------------------------
; nbox_cmd_spawnc
;
; Diagnostic command:
;   SPAWNC
;
; Expected test flow:
;   - allocates a resident setup child with a fixed diagnostic entry
;   - inherits fd 0, 1, 2 into that child
;   - commits the child so the scheduler may run it
;   - yields once so the committed child can print and exit
; ------------------------------------------------------------
.proc nbox_cmd_spawnc
    lda #<nbox_spawn_msg_commit_start
    ldx #>nbox_spawn_msg_commit_start
    ldy #NBOX_SPAWN_MSG_COMMIT_START_LEN
    jsr nbox_print_msg

    ; Reuse the shared allocation argument block, but select the
    ; committing diagnostic child entry for this command.
    lda #<nbox_spawncommit_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry
    lda #>nbox_spawncommit_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry + 1
    lda #SPAWN_FLAGS_NONE
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::flags
    lda #$FF
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::result_pid

    SYSCALL nbox_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_alloc_fail
    ldx #>nbox_spawn_msg_alloc_fail
    ldy #NBOX_SPAWN_MSG_ALLOC_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@allocated:
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_commit_pid
    ldx #>nbox_spawn_msg_commit_pid
    ldy #NBOX_SPAWN_MSG_COMMIT_PID_LEN
    jsr nbox_print_msg

    lda nbox_spawn_child_pid
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    jsr nbox_spawn_inherit_stdio
    bcs @fd_fail

    jsr nbox_spawn_commit_child
    bcc @commit_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_commit_fail
    ldx #>nbox_spawn_msg_commit_fail
    ldy #NBOX_SPAWN_MSG_COMMIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@commit_ok:
    lda #<nbox_spawn_msg_commit_ok
    ldx #>nbox_spawn_msg_commit_ok
    ldy #NBOX_SPAWN_MSG_COMMIT_OK_LEN
    jsr nbox_print_msg

    ; Give the scheduler an immediate opportunity to run the committed
    ; child, then reap it so SPAWNC does not leave a zombie behind.
    jsr sys_yield

    lda nbox_spawn_child_pid
    jsr sys_waitpid
    bcc @wait_reaped

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_wait_fail
    ldx #>nbox_spawn_msg_wait_fail
    ldy #NBOX_SPAWN_MSG_WAIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@wait_reaped:
    lda #$FF
    sta nbox_spawn_child_pid

    clc
    rts

@fd_fail:
    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_fd_fail
    ldx #>nbox_spawn_msg_fd_fail
    ldy #NBOX_SPAWN_MSG_FD_FAIL_LEN
    jmp nbox_spawn_print_errno_line
.endproc

; ------------------------------------------------------------
; nbox_cmd_spawnw
;
; Diagnostic command:
;   SPAWNW
;
; Expected test flow:
;   - allocates a resident setup child with fixed diagnostic entry
;   - inherits fd 0, 1, 2 into that child
;   - commits the child
;   - yields once so the child runs and exits as a waitable zombie
;   - pauses for monitor inspection of PROC_ZOMBIE
;   - calls SYS_WAITPID and prints the returned exit status
; ------------------------------------------------------------
.proc nbox_cmd_spawnw
    lda #<nbox_spawn_msg_wait_start
    ldx #>nbox_spawn_msg_wait_start
    ldy #NBOX_SPAWN_MSG_WAIT_START_LEN
    jsr nbox_print_msg

    lda #<nbox_spawnwait_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry
    lda #>nbox_spawnwait_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry + 1
    lda #SPAWN_FLAGS_NONE
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::flags
    lda #$FF
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::result_pid

    SYSCALL nbox_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_alloc_fail
    ldx #>nbox_spawn_msg_alloc_fail
    ldy #NBOX_SPAWN_MSG_ALLOC_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@allocated:
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_wait_pid
    ldx #>nbox_spawn_msg_wait_pid
    ldy #NBOX_SPAWN_MSG_WAIT_PID_LEN
    jsr nbox_print_msg

    lda nbox_spawn_child_pid
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    jsr nbox_spawn_inherit_stdio
    bcs @fd_fail

    jsr nbox_spawn_commit_child
    bcc @commit_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_commit_fail
    ldx #>nbox_spawn_msg_commit_fail
    ldy #NBOX_SPAWN_MSG_COMMIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@commit_ok:
    jsr sys_yield

    lda #<nbox_spawn_msg_wait_zombie
    ldx #>nbox_spawn_msg_wait_zombie
    ldy #NBOX_SPAWN_MSG_WAIT_ZOMBIE_LEN
    jsr nbox_print_msg

    jsr nbox_spawn_wait_for_operator

    lda nbox_spawn_child_pid
    jsr sys_waitpid
    bcc @wait_ok

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_wait_fail
    ldx #>nbox_spawn_msg_wait_fail
    ldy #NBOX_SPAWN_MSG_WAIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@wait_ok:
    pha
    lda #<nbox_spawn_msg_wait_status
    ldx #>nbox_spawn_msg_wait_status
    ldy #NBOX_SPAWN_MSG_WAIT_STATUS_LEN
    jsr nbox_print_msg

    pla
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    lda #$FF
    sta nbox_spawn_child_pid

    clc
    rts

@fd_fail:
    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_fd_fail
    ldx #>nbox_spawn_msg_fd_fail
    ldy #NBOX_SPAWN_MSG_FD_FAIL_LEN
    jmp nbox_spawn_print_errno_line
.endproc

; ------------------------------------------------------------
; nbox_cmd_spawni
;
; Diagnostic command:
;   SPAWNI
;
; Expected test flow:
;   - allocates a resident setup child with entry nbox_child_entry
;   - assigns launch id NBOX_APPLET_HELP
;   - inherits fd 0, 1, 2 into that child
;   - commits the child
;   - waits for the child to exit
;
; The child proves the generic nbox_child_entry can retrieve a parent-
; assigned launch id, dispatch the selected no-argument resident applet,
; write through inherited stdout, and exit/reap through WAITPID.
; ------------------------------------------------------------
.proc nbox_cmd_spawni
    lda #<nbox_spawn_msg_nbox_start
    ldx #>nbox_spawn_msg_nbox_start
    ldy #NBOX_SPAWN_MSG_NBOX_START_LEN
    jsr nbox_print_msg

    lda #<nbox_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry
    lda #>nbox_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry + 1
    lda #SPAWN_FLAGS_NONE
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::flags
    lda #$FF
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::result_pid

    SYSCALL nbox_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_alloc_fail
    ldx #>nbox_spawn_msg_alloc_fail
    ldy #NBOX_SPAWN_MSG_ALLOC_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@allocated:
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_nbox_pid
    ldx #>nbox_spawn_msg_nbox_pid
    ldy #NBOX_SPAWN_MSG_NBOX_PID_LEN
    jsr nbox_print_msg

    lda nbox_spawn_child_pid
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    jsr nbox_spawn_set_launch_help
    bcc @launch_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_nbox_set_fail
    ldx #>nbox_spawn_msg_nbox_set_fail
    ldy #NBOX_SPAWN_MSG_NBOX_SET_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@launch_ok:
    ; fd 0/1/2 are inherited by default by SYS_SPAWN_ALLOC_RESIDENT.
    jsr nbox_spawn_commit_child
    bcc @commit_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_commit_fail
    ldx #>nbox_spawn_msg_commit_fail
    ldy #NBOX_SPAWN_MSG_COMMIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@commit_ok:
    lda #<nbox_spawn_msg_nbox_commit_ok
    ldx #>nbox_spawn_msg_nbox_commit_ok
    ldy #NBOX_SPAWN_MSG_NBOX_COMMIT_OK_LEN
    jsr nbox_print_msg

    jsr sys_yield

    lda nbox_spawn_child_pid
    jsr sys_waitpid
    bcc @wait_ok

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_wait_fail
    ldx #>nbox_spawn_msg_wait_fail
    ldy #NBOX_SPAWN_MSG_WAIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@wait_ok:
    pha
    lda #<nbox_spawn_msg_nbox_status
    ldx #>nbox_spawn_msg_nbox_status
    ldy #NBOX_SPAWN_MSG_NBOX_STATUS_LEN
    jsr nbox_print_msg

    pla
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    lda #$FF
    sta nbox_spawn_child_pid

    clc
    rts

@fd_fail:
    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_fd_fail
    ldx #>nbox_spawn_msg_fd_fail
    ldy #NBOX_SPAWN_MSG_FD_FAIL_LEN
    jmp nbox_spawn_print_errno_line
.endproc



; ------------------------------------------------------------
; nbox_cmd_spawnl
;
; Diagnostic command:
;   SPAWNL
;
; Expected test flow:
;   - allocates a resident setup child with entry nbox_child_entry
;   - assigns launch id NBOX_APPLET_LS
;   - assigns argc=1 / arg0="."
;   - relies on default fd 0/1/2 inheritance from spawn allocation
;   - commits and waits for the child
; ------------------------------------------------------------
.proc nbox_cmd_spawnl
    lda #<nbox_spawn_msg_ls_start
    ldx #>nbox_spawn_msg_ls_start
    ldy #NBOX_SPAWN_MSG_LS_START_LEN
    jsr nbox_print_msg

    lda #<nbox_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry
    lda #>nbox_child_entry
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::entry + 1
    lda #SPAWN_FLAGS_NONE
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::flags
    lda #$FF
    sta nbox_spawn_alloc_args + spawn_alloc_resident_args::result_pid

    SYSCALL nbox_spawn_alloc_args, sys_spawn_alloc_resident
    bcc @allocated

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_alloc_fail
    ldx #>nbox_spawn_msg_alloc_fail
    ldy #NBOX_SPAWN_MSG_ALLOC_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@allocated:
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_ls_pid
    ldx #>nbox_spawn_msg_ls_pid
    ldy #NBOX_SPAWN_MSG_LS_PID_LEN
    jsr nbox_print_msg

    lda nbox_spawn_child_pid
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    jsr nbox_spawn_set_launch_ls
    bcc @launch_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_ls_set_fail
    ldx #>nbox_spawn_msg_ls_set_fail
    ldy #NBOX_SPAWN_MSG_LS_SET_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@launch_ok:
    jsr nbox_spawn_set_args_ls_dot
    bcc @args_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_ls_set_fail
    ldx #>nbox_spawn_msg_ls_set_fail
    ldy #NBOX_SPAWN_MSG_LS_SET_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@args_ok:
    jsr nbox_spawn_commit_child
    bcc @commit_ok

    sty nbox_spawn_errno
    jsr nbox_spawn_abort_child

    lda #<nbox_spawn_msg_commit_fail
    ldx #>nbox_spawn_msg_commit_fail
    ldy #NBOX_SPAWN_MSG_COMMIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@commit_ok:
    lda #<nbox_spawn_msg_ls_commit_ok
    ldx #>nbox_spawn_msg_ls_commit_ok
    ldy #NBOX_SPAWN_MSG_LS_COMMIT_OK_LEN
    jsr nbox_print_msg

    jsr sys_yield

    lda nbox_spawn_child_pid
    jsr sys_waitpid
    bcc @wait_ok

    sty nbox_spawn_errno
    lda #<nbox_spawn_msg_wait_fail
    ldx #>nbox_spawn_msg_wait_fail
    ldy #NBOX_SPAWN_MSG_WAIT_FAIL_LEN
    jmp nbox_spawn_print_errno_line

@wait_ok:
    pha
    lda #<nbox_spawn_msg_ls_status
    ldx #>nbox_spawn_msg_ls_status
    ldy #NBOX_SPAWN_MSG_LS_STATUS_LEN
    jsr nbox_print_msg

    pla
    jsr nbox_print_hex_byte
    jsr nbox_print_cr

    lda #$FF
    sta nbox_spawn_child_pid

    clc
    rts
.endproc
