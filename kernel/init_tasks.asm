; ============================================================
; init_tasks.asm
; NEOX - initial runnable task setup
;
; Purpose:
;   Creates initial user/test tasks.
;
; Model:
;   - PID 0 is the idle process, initialized by scheduler/main.
;   - Monitor is not a process.
;   - Normal tasks are allocated from PID 1 upward.
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "scheduler_defs.inc"
.include "bios.inc"

.export tasks_init
.export task1
.export task2

.import scheduler_create_process

.import test_ctr1
.import test_ctr2
.import test_turn

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Process-create control blocks
;
; Layout from proc_create_args:
;   context   .byte
;   reserved  .byte
;   entry     .word
; ------------------------------------------------------------

task1_create:
    .byte $01
    .byte $00
    .word task1

task2_create:
    .byte $02
    .byte $00
    .word task2

task3_create:
    .byte $03
    .byte $00
    .word task3
	
; ------------------------------------------------------------
; tasks_init
;
; Purpose:
;   Populate the process table with:
;     PID 1 = task1
;     PID 2 = task2
;
; PID 0 is not created here. It is the idle process.
; ------------------------------------------------------------

.proc tasks_init
    stz test_ctr1
    stz test_ctr2
    stz test_turn

    ldx #<task1_create
    ldy #>task1_create
    jsr scheduler_create_process

    ldx #<task2_create
    ldy #>task2_create
    jsr scheduler_create_process

    ldx #<task3_create
    ldy #>task3_create
    jmp scheduler_create_process
.endproc

; ------------------------------------------------------------
; task2
; ------------------------------------------------------------

.proc task2
@loop:
    inc test_ctr2
    lda #$02
    sta test_turn
	lda #48
	jsr sys_sleep
    bra @loop
.endproc

; ------------------------------------------------------------
; task3
; ------------------------------------------------------------

.proc task3
@loop:
    ; read a char from console
    jsr BIOS_GETCHAR
	
    ; echo received character
    jsr BIOS_PUTCHAR
	
	; when q exit
	cmp #'q'
	bne @loop
	
	jmp sys_exit
.endproc

; ------------------------------------------------------------
; task1_write_stdout
;
; Input:
;   A/X = string pointer
;   Y   = length
;
; Output:
;   syscall result preserved
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
; task1_close_fd
;
; Input:
;   A = fd
; ------------------------------------------------------------

.proc task1_close_fd
    jmp sys_close
.endproc

; ------------------------------------------------------------
; task1_write_stdin
;
; Input:
;   A/X = string pointer
;   Y   = length
; ------------------------------------------------------------

.proc task1_write_stdin
    sta task1_rw_args + rw_args::buf_ptr
    stx task1_rw_args + rw_args::buf_ptr + 1

    sty task1_rw_args + rw_args::len
    stz task1_rw_args + rw_args::len + 1

    lda #0
    sta task1_rw_args + rw_args::fd

    ldx #<task1_rw_args
    ldy #>task1_rw_args
    jmp sys_write
.endproc

; ------------------------------------------------------------
; task1_read_stdout
;
; Input:
;   A/X = buffer pointer
;   Y   = length
; ------------------------------------------------------------

.proc task1_read_stdout
    sta task1_rw_args + rw_args::buf_ptr
    stx task1_rw_args + rw_args::buf_ptr + 1

    sty task1_rw_args + rw_args::len
    stz task1_rw_args + rw_args::len + 1

    lda #1
    sta task1_rw_args + rw_args::fd

    ldx #<task1_rw_args
    ldy #>task1_rw_args
    jmp sys_read
.endproc

; ------------------------------------------------------------
; task1
;
; Test:
;   - write stdout before close
;   - close stdout
;   - verify write stdout fails
;   - verify stderr still works
; ------------------------------------------------------------

.proc task1
    ; Write to stdout before close.
    lda #<task1_msg_before
    ldx #>task1_msg_before
    ldy #task1_msg_before_len
    jsr task1_write_stdout

    ; write(0, ...) must fail because stdin is read-only.
    lda #<task1_msg_write_stdin
    ldx #>task1_msg_write_stdin
    ldy #task1_msg_write_stdin_len
    jsr task1_write_stdin
    bcs @write_stdin_failed_ok

    lda #<task1_msg_write_stdin_bug
    ldx #>task1_msg_write_stdin_bug
    ldy #task1_msg_write_stdin_bug_len
    jsr task1_write_stderr
    bra @after_write_stdin_test

@write_stdin_failed_ok:
    lda #<task1_msg_write_stdin_ok
    ldx #>task1_msg_write_stdin_ok
    ldy #task1_msg_write_stdin_ok_len
    jsr task1_write_stderr

@after_write_stdin_test:
    ; read(1, ...) must fail because stdout is write-only.
    lda #<task1_read_buf
    ldx #>task1_read_buf
    ldy #1
    jsr task1_read_stdout
    bcs @read_stdout_failed_ok

    lda #<task1_msg_read_stdout_bug
    ldx #>task1_msg_read_stdout_bug
    ldy #task1_msg_read_stdout_bug_len
    jsr task1_write_stderr
    bra @after_read_stdout_test

@read_stdout_failed_ok:
    lda #<task1_msg_read_stdout_ok
    ldx #>task1_msg_read_stdout_ok
    ldy #task1_msg_read_stdout_ok_len
    jsr task1_write_stderr

@after_read_stdout_test:
    ; Close stdout: fd 1.
    lda #1
    jsr task1_close_fd

    ; This write must fail because fd 1 is now closed.
    lda #<task1_msg_after
    ldx #>task1_msg_after
    ldy #task1_msg_after_len
    jsr task1_write_stdout

    bcs @stdout_failed_ok

    ; If write succeeded, that is a bug.
    lda #<task1_msg_bug
    ldx #>task1_msg_bug
    ldy #task1_msg_bug_len
    jsr task1_write_stderr
    bra @loop

@stdout_failed_ok:
    ; write(1) failed as expected.
    lda #<task1_msg_ok
    ldx #>task1_msg_ok
    ldy #task1_msg_ok_len
    jsr task1_write_stderr

    ; Now prove stderr itself still works after stdout was closed.
    lda #<task1_msg_stderr_ok
    ldx #>task1_msg_stderr_ok
    ldy #task1_msg_stderr_ok_len
    jsr task1_write_stderr

@loop:
    ; Keep task alive.
    jsr sys_yield
    bra @loop
.endproc

;.segment "USER_DATA"

task1_rw_args:
    .tag rw_args

task1_msg_before:
    .byte "T1: stdout before close", 13, 10
task1_msg_before_len = * - task1_msg_before

task1_msg_after:
    .byte "T1: stdout after close - SHOULD NOT PRINT", 13, 10
task1_msg_after_len = * - task1_msg_after

task1_msg_ok:
    .byte "T1: write(1) failed after close - OK", 13, 10
task1_msg_ok_len = * - task1_msg_ok

task1_msg_bug:
    .byte "T1: BUG - write(1) succeeded after close", 13, 10
task1_msg_bug_len = * - task1_msg_bug

task1_msg_stderr_ok:
    .byte "T1: stderr still works after close(1)", 13, 10
task1_msg_stderr_ok_len = * - task1_msg_stderr_ok

task1_read_buf:
    .res 1

task1_msg_write_stdin:
    .byte "T1: write to stdin - SHOULD NOT PRINT", 13, 10
task1_msg_write_stdin_len = * - task1_msg_write_stdin

task1_msg_write_stdin_ok:
    .byte "T1: write(0) failed - OK", 13, 10
task1_msg_write_stdin_ok_len = * - task1_msg_write_stdin_ok

task1_msg_write_stdin_bug:
    .byte "T1: BUG - write(0) succeeded", 13, 10
task1_msg_write_stdin_bug_len = * - task1_msg_write_stdin_bug

task1_msg_read_stdout_ok:
    .byte "T1: read(1) failed - OK", 13, 10
task1_msg_read_stdout_ok_len = * - task1_msg_read_stdout_ok

task1_msg_read_stdout_bug:
    .byte "T1: BUG - read(1) succeeded", 13, 10
task1_msg_read_stdout_bug_len = * - task1_msg_read_stdout_bug
