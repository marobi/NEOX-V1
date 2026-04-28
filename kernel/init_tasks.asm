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

.include "scheduler_defs.inc"

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
    jmp scheduler_create_process
.endproc

; ------------------------------------------------------------
; task1
; ------------------------------------------------------------

.proc task1
@loop:
    inc test_ctr1
    lda #$01
    sta test_turn
    bra @loop
.endproc

; ------------------------------------------------------------
; task2
; ------------------------------------------------------------

.proc task2
@loop:
    inc test_ctr2
    lda #$02
    sta test_turn
    bra @loop
.endproc
