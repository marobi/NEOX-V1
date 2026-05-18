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
;   - User process code lives in USER_TEXT, not KERN_TEXT.
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"

.export tasks_init

.import scheduler_create_process

; ------------------------------------------------------------
; Static test user image entry points
;
; These addresses must match the user image linker script.
; ------------------------------------------------------------

USER_TASK1_ENTRY = $2000
USER_TASK2_ENTRY = $2400
USER_TASK3_ENTRY = $2800

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
    .word USER_TASK1_ENTRY

task2_create:
    .byte $02
    .byte $00
    .word USER_TASK2_ENTRY

task3_create:
    .byte $03
    .byte $00
    .word USER_TASK3_ENTRY
	
; ============================================================
; init_tasks.asm
; NEOX - boot user process creation from user image table
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"

.export tasks_init

.import init_task_count
.import init_task_ptr

.import scheduler_create_process

.segment "KERN_TEXT"

USER_IMAGE_TABLE = $2000

USER_MAGIC0      = USER_IMAGE_TABLE + 0
USER_MAGIC1      = USER_IMAGE_TABLE + 1
USER_VERSION     = USER_IMAGE_TABLE + 2
USER_TASK_COUNT  = USER_IMAGE_TABLE + 3
USER_TASK_TABLE  = USER_IMAGE_TABLE + 4

USER_ENTRY_SIZE  = 4

.proc tasks_init
    ; Validate magic.
    lda USER_MAGIC0
    cmp #'N'
    bne @bad_user_image

    lda USER_MAGIC1
    cmp #'X'
    bne @bad_user_image

    ; Validate version.
    lda USER_VERSION
    cmp #$01
    bne @bad_user_image

    lda USER_TASK_COUNT
    beq @done

    sta init_task_count

    lda #<USER_TASK_TABLE
    sta init_task_ptr
    lda #>USER_TASK_TABLE
    sta init_task_ptr+1

@loop:
    ldx init_task_ptr
    ldy init_task_ptr+1
    jsr scheduler_create_process

    clc
    lda init_task_ptr
    adc #USER_ENTRY_SIZE
    sta init_task_ptr

    lda init_task_ptr+1
    adc #0
    sta init_task_ptr+1

    dec init_task_count
    bne @loop

@done:
    clc
    rts

@bad_user_image:
    ; For now, trap hard. Later print a boot error.
    bra @bad_user_image
.endproc
