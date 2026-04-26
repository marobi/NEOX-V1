; ============================================================
; init_tasks.asm
; NEOX - initial process table setup and scheduler test tasks
;
; Purpose:
;   Defines pid 0 as the monitor/supervisor process and creates
;   the initial runnable tasks through scheduler_create_process
;   using an explicit process-create control block.
;
; Design:
;   - pid 0 = monitor process descriptor
;   - pid 1 = task1
;   - pid 2 = task2
;   - no ptr0 usage
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

MONITOR_ENTRY = $B000

.segment "KERN_TEXT"

; ------------------------------------------------------------
; Process-create control blocks
;
; Layout from proc_create_args:
;   context   .byte
;   reserved  .byte
;   entry     .word
; ------------------------------------------------------------

monitor_create:
    .byte $00		; context
    .byte $00
    .word MONITOR_ENTRY	; start address

task1_create:
    .byte $01		; context
    .byte $00
    .word task1		; start address

task2_create:
    .byte $02		; context
    .byte $00
    .word task2		; start address

; ------------------------------------------------------------
; tasks_init
;
; Purpose:
;   Populate the process table with:
;     pid 0 = monitor
;     pid 1 = task1
;     pid 2 = task2
;
; Calling convention of scheduler_create_process:
;   A   = pid
;   X/Y = pointer to proc_create_args block
; ------------------------------------------------------------

.proc tasks_init
    ; Reset shared test state
    stz test_ctr1
    stz test_ctr2
    stz test_turn

    ; --------------------------------------------------------
    ; Create pid 0 = monitor
    ; --------------------------------------------------------
    ldx #<monitor_create
    ldy #>monitor_create
    jsr scheduler_create_process

    ; --------------------------------------------------------
    ; Create pid 1 = task1
    ; --------------------------------------------------------
    ldx #<task1_create
    ldy #>task1_create
    jsr scheduler_create_process

    ; --------------------------------------------------------
    ; Create pid 2 = task2
    ; --------------------------------------------------------
    ldx #<task2_create
    ldy #>task2_create
    jmp scheduler_create_process
.endproc

; ------------------------------------------------------------
; task1
;
; Purpose:
;   Simple scheduler test task running in context 1.
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
;
; Purpose:
;   Simple scheduler test task running in context 2.
; ------------------------------------------------------------

.proc task2
@loop:
    inc test_ctr2
    lda #$02
    sta test_turn
    bra @loop
.endproc
