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

.proc task1
	lda #5
	jsr sys_sleep
@loop:
    inc test_ctr1
    lda #$01
    sta test_turn
	lda #13
	jsr sys_sleep
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

