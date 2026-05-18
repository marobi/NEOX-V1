; ============================================================
; task3.asm
; NEOX console echo task
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "bios.inc"

.export user_task1_entry

.segment "USER_TEXT"

.proc user_task1_entry

; ------------------------------------------------------------
; task1
;
; FD dup/dup2 edge-case regression test.
;
; Initial expected FD state:
;   0:r  1:w  2:w  -
;
; Tests:
;   dup2(1,1)  -> returns 1, no refcount change
;   dup(3)     -> EBADF
;   dup2(3,1)  -> EBADF, fd 1 still valid
;   dup2(1,4)  -> EBADF, fd 1 still valid
;
; Final expected FD state:
;   0:r  1:w  2:w  -
; ------------------------------------------------------------

    lda #<task1_msg_start
    ldx #>task1_msg_start
    ldy #task1_msg_start_len
    jsr task1_write_stdout

    ; --------------------------------------------------------
    ; Test 1: dup2(1,1)
    ; --------------------------------------------------------

    lda #1
    ldy #1
    jsr task1_dup2_fd
    bcc @dup2_same_returned

    lda #<task1_msg_dup2_same_failed
    ldx #>task1_msg_dup2_same_failed
    ldy #task1_msg_dup2_same_failed_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_same_returned:
    cmp #1
    beq @dup2_same_ok

    lda #<task1_msg_dup2_same_wrong_fd
    ldx #>task1_msg_dup2_same_wrong_fd
    ldy #task1_msg_dup2_same_wrong_fd_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_same_ok:
    lda #<task1_msg_dup2_same_ok
    ldx #>task1_msg_dup2_same_ok
    ldy #task1_msg_dup2_same_ok_len
    jsr task1_write_stdout

    ; fd 1 must still work.
    lda #<task1_msg_fd1_after_dup2_same
    ldx #>task1_msg_fd1_after_dup2_same
    ldy #task1_msg_fd1_after_dup2_same_len
    jsr task1_write_stdout
    bcc @fd1_after_dup2_same_ok

    lda #<task1_msg_fd1_after_dup2_same_failed
    ldx #>task1_msg_fd1_after_dup2_same_failed
    ldy #task1_msg_fd1_after_dup2_same_failed_len
    jsr task1_write_stderr
    jmp @tests_done

@fd1_after_dup2_same_ok:

    ; --------------------------------------------------------
    ; Test 2: dup(3), where fd 3 is closed
    ; --------------------------------------------------------

    lda #3
    jsr task1_dup_fd
    bcs @dup_closed_failed_as_expected

    lda #<task1_msg_dup_closed_bug
    ldx #>task1_msg_dup_closed_bug
    ldy #task1_msg_dup_closed_bug_len
    jsr task1_write_stdout
    jmp @tests_done

@dup_closed_failed_as_expected:
    cpy #EBADF
    beq @dup_closed_ok

    lda #<task1_msg_dup_closed_wrong_errno
    ldx #>task1_msg_dup_closed_wrong_errno
    ldy #task1_msg_dup_closed_wrong_errno_len
    jsr task1_write_stdout
    jmp @tests_done

@dup_closed_ok:
    lda #<task1_msg_dup_closed_ok
    ldx #>task1_msg_dup_closed_ok
    ldy #task1_msg_dup_closed_ok_len
    jsr task1_write_stdout

    ; --------------------------------------------------------
    ; Test 3: dup2(3,1), old fd closed
    ; --------------------------------------------------------

    lda #3
    ldy #1
    jsr task1_dup2_fd
    bcs @dup2_old_closed_failed_as_expected

    lda #<task1_msg_dup2_old_closed_bug
    ldx #>task1_msg_dup2_old_closed_bug
    ldy #task1_msg_dup2_old_closed_bug_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_old_closed_failed_as_expected:
    cpy #EBADF
    beq @dup2_old_closed_ok

    lda #<task1_msg_dup2_old_closed_wrong_errno
    ldx #>task1_msg_dup2_old_closed_wrong_errno
    ldy #task1_msg_dup2_old_closed_wrong_errno_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_old_closed_ok:
    lda #<task1_msg_dup2_old_closed_ok
    ldx #>task1_msg_dup2_old_closed_ok
    ldy #task1_msg_dup2_old_closed_ok_len
    jsr task1_write_stdout

    ; fd 1 must still work after failed dup2.
    lda #<task1_msg_fd1_after_failed_dup2_old
    ldx #>task1_msg_fd1_after_failed_dup2_old
    ldy #task1_msg_fd1_after_failed_dup2_old_len
    jsr task1_write_stdout
    bcc @fd1_after_failed_dup2_old_ok

    lda #<task1_msg_fd1_after_failed_dup2_old_failed
    ldx #>task1_msg_fd1_after_failed_dup2_old_failed
    ldy #task1_msg_fd1_after_failed_dup2_old_failed_len
    jsr task1_write_stderr
    jmp @tests_done

@fd1_after_failed_dup2_old_ok:

    ; --------------------------------------------------------
    ; Test 4: dup2(1,4), new fd out of range
    ; MAX_FDS = 4, valid fds are 0..3.
    ; --------------------------------------------------------

    lda #1
    ldy #4
    jsr task1_dup2_fd
    bcs @dup2_new_range_failed_as_expected

    lda #<task1_msg_dup2_new_range_bug
    ldx #>task1_msg_dup2_new_range_bug
    ldy #task1_msg_dup2_new_range_bug_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_new_range_failed_as_expected:
    cpy #EBADF
    beq @dup2_new_range_ok

    lda #<task1_msg_dup2_new_range_wrong_errno
    ldx #>task1_msg_dup2_new_range_wrong_errno
    ldy #task1_msg_dup2_new_range_wrong_errno_len
    jsr task1_write_stdout
    jmp @tests_done

@dup2_new_range_ok:
    lda #<task1_msg_dup2_new_range_ok
    ldx #>task1_msg_dup2_new_range_ok
    ldy #task1_msg_dup2_new_range_ok_len
    jsr task1_write_stdout

    ; fd 1 must still work after failed range dup2.
    lda #<task1_msg_fd1_after_failed_dup2_range
    ldx #>task1_msg_fd1_after_failed_dup2_range
    ldy #task1_msg_fd1_after_failed_dup2_range_len
    jsr task1_write_stdout
    bcc @all_ok

    lda #<task1_msg_fd1_after_failed_dup2_range_failed
    ldx #>task1_msg_fd1_after_failed_dup2_range_failed
    ldy #task1_msg_fd1_after_failed_dup2_range_failed_len
    jsr task1_write_stderr
    jmp @tests_done

@all_ok:
    lda #<task1_msg_all_ok
    ldx #>task1_msg_all_ok
    ldy #task1_msg_all_ok_len
    jsr task1_write_stdout

@tests_done:
    lda #100
	jsr sys_sleep
    bra @tests_done
.endproc

; ------------------------------------------------------------
; task1_write_stdout
;
; Input:
;   A/X = string pointer
;   Y   = length
; ------------------------------------------------------------

.proc task1_write_stdout
    sta task1_rw_args + rw_args::buf_ptr
    stx task1_rw_args + rw_args::buf_ptr + 1

    sty task1_rw_args + rw_args::len
    stz task1_rw_args + rw_args::len + 1

    lda #1
    sta task1_rw_args + rw_args::fd

    ldx #<task1_rw_args
    ldy #>task1_rw_args
    jmp sys_write
.endproc

; ------------------------------------------------------------
; task1_write_stderr
;
; Input:
;   A/X = string pointer
;   Y   = length
; ------------------------------------------------------------

.proc task1_write_stderr
    sta task1_rw_args + rw_args::buf_ptr
    stx task1_rw_args + rw_args::buf_ptr + 1

    sty task1_rw_args + rw_args::len
    stz task1_rw_args + rw_args::len + 1

    lda #2
    sta task1_rw_args + rw_args::fd

    ldx #<task1_rw_args
    ldy #>task1_rw_args
    jmp sys_write
.endproc

; ------------------------------------------------------------
; task1_dup_fd
;
; Input:
;   A = old fd
;
; Output:
;   C clear = success, A = new fd
;   C set   = failure, Y = errno
; ------------------------------------------------------------

.proc task1_dup_fd
    jmp sys_dup
.endproc

; ------------------------------------------------------------
; task1_dup2_fd
;
; Input:
;   A = old fd
;   Y = new fd
;
; Output:
;   C clear = success, A = new fd
;   C set   = failure, Y = errno
; ------------------------------------------------------------

.proc task1_dup2_fd
    jmp sys_dup2
.endproc

.segment "USER_DATA"

task1_rw_args:
    .tag rw_args

task1_msg_start:
    .byte "T1: dup edge test start", 13
task1_msg_start_len = * - task1_msg_start

task1_msg_dup2_same_ok:
    .byte "T1: dup2(1,1) returned 1 - OK", 13
task1_msg_dup2_same_ok_len = * - task1_msg_dup2_same_ok

task1_msg_dup2_same_failed:
    .byte "T1: BUG - dup2(1,1) failed", 13
task1_msg_dup2_same_failed_len = * - task1_msg_dup2_same_failed

task1_msg_dup2_same_wrong_fd:
    .byte "T1: BUG - dup2(1,1) returned wrong fd", 13
task1_msg_dup2_same_wrong_fd_len = * - task1_msg_dup2_same_wrong_fd

task1_msg_fd1_after_dup2_same:
    .byte "T1: fd 1 works after dup2(1,1)", 13
task1_msg_fd1_after_dup2_same_len = * - task1_msg_fd1_after_dup2_same

task1_msg_fd1_after_dup2_same_failed:
    .byte "T1: BUG - fd 1 failed after dup2(1,1)", 13
task1_msg_fd1_after_dup2_same_failed_len = * - task1_msg_fd1_after_dup2_same_failed

task1_msg_dup_closed_ok:
    .byte "T1: dup(3) failed EBADF - OK", 13
task1_msg_dup_closed_ok_len = * - task1_msg_dup_closed_ok

task1_msg_dup_closed_bug:
    .byte "T1: BUG - dup(3) succeeded", 13
task1_msg_dup_closed_bug_len = * - task1_msg_dup_closed_bug

task1_msg_dup_closed_wrong_errno:
    .byte "T1: BUG - dup(3) wrong errno", 13
task1_msg_dup_closed_wrong_errno_len = * - task1_msg_dup_closed_wrong_errno

task1_msg_dup2_old_closed_ok:
    .byte "T1: dup2(3,1) failed EBADF - OK", 13
task1_msg_dup2_old_closed_ok_len = * - task1_msg_dup2_old_closed_ok

task1_msg_dup2_old_closed_bug:
    .byte "T1: BUG - dup2(3,1) succeeded", 13
task1_msg_dup2_old_closed_bug_len = * - task1_msg_dup2_old_closed_bug

task1_msg_dup2_old_closed_wrong_errno:
    .byte "T1: BUG - dup2(3,1) wrong errno", 13
task1_msg_dup2_old_closed_wrong_errno_len = * - task1_msg_dup2_old_closed_wrong_errno

task1_msg_fd1_after_failed_dup2_old:
    .byte "T1: fd 1 works after failed dup2(3,1)", 13
task1_msg_fd1_after_failed_dup2_old_len = * - task1_msg_fd1_after_failed_dup2_old

task1_msg_fd1_after_failed_dup2_old_failed:
    .byte "T1: BUG - fd 1 failed after failed dup2(3,1)", 13
task1_msg_fd1_after_failed_dup2_old_failed_len = * - task1_msg_fd1_after_failed_dup2_old_failed

task1_msg_dup2_new_range_ok:
    .byte "T1: dup2(1,4) failed EBADF - OK", 13
task1_msg_dup2_new_range_ok_len = * - task1_msg_dup2_new_range_ok

task1_msg_dup2_new_range_bug:
    .byte "T1: BUG - dup2(1,4) succeeded", 13
task1_msg_dup2_new_range_bug_len = * - task1_msg_dup2_new_range_bug

task1_msg_dup2_new_range_wrong_errno:
    .byte "T1: BUG - dup2(1,4) wrong errno", 13
task1_msg_dup2_new_range_wrong_errno_len = * - task1_msg_dup2_new_range_wrong_errno

task1_msg_fd1_after_failed_dup2_range:
    .byte "T1: fd 1 works after failed dup2(1,4)", 13
task1_msg_fd1_after_failed_dup2_range_len = * - task1_msg_fd1_after_failed_dup2_range

task1_msg_fd1_after_failed_dup2_range_failed:
    .byte "T1: BUG - fd 1 failed after failed dup2(1,4)", 13
task1_msg_fd1_after_failed_dup2_range_failed_len = * - task1_msg_fd1_after_failed_dup2_range_failed

task1_msg_all_ok:
    .byte "T1: dup edge tests complete - OK", 13
task1_msg_all_ok_len = * - task1_msg_all_ok
