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
.export nbox_spawntest_child_entry
.export nbox_spawncommit_child_entry

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

nbox_spawn_child_args:
    .byte $FF

nbox_spawn_read_args:
    .byte STDIN
    .byte 0
    .word nbox_spawn_key_buf
    .word 1

nbox_spawn_msg_start:
    .byte "SPAWN: ALLOC", 13
NBOX_SPAWN_MSG_START_LEN = * - nbox_spawn_msg_start

nbox_spawn_msg_pid:
    .byte "SPAWN: CHILD PID $"
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

nbox_spawn_msg_commit_ok:
    .byte "SPAWNC: COMMIT OK", 13
NBOX_SPAWN_MSG_COMMIT_OK_LEN = * - nbox_spawn_msg_commit_ok

nbox_spawn_msg_commit_fail:
    .byte "SPAWNC: COMMIT FAIL $"
NBOX_SPAWN_MSG_COMMIT_FAIL_LEN = * - nbox_spawn_msg_commit_fail

nbox_spawn_msg_child_run:
    .byte "SPAWNC CHILD RUN", 13
NBOX_SPAWN_MSG_CHILD_RUN_LEN = * - nbox_spawn_msg_child_run

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

    lda #<nbox_spawn_msg_pid
    ldx #>nbox_spawn_msg_pid
    ldy #NBOX_SPAWN_MSG_PID_LEN
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
    lda #$FF
    sta nbox_spawn_child_pid

    lda #<nbox_spawn_msg_commit_ok
    ldx #>nbox_spawn_msg_commit_ok
    ldy #NBOX_SPAWN_MSG_COMMIT_OK_LEN
    jsr nbox_print_msg

    ; Give the scheduler an immediate opportunity to run the committed
    ; child before the shell prints another prompt.
    jsr sys_yield

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

