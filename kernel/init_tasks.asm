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

.include "config.inc"
.include "kernel.inc"
.include "scheduler_defs.inc"

.export tasks_init

.import proc_create

.import init_task_count
.import init_task_ptr

.segment "KERN_TEXT"

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
    jsr proc_create

    clc
    lda init_task_ptr
    adc #USER_ENTRY_SIZE
    sta init_task_ptr

    lda init_task_ptr+1
    adc #0
    sta init_task_ptr+1

    dec init_task_count
    bne @loop

    ; Only wire static inter-process test pipe when PID 1 and PID 2 exist.
    lda USER_TASK_COUNT
    cmp #2
    bcc @done

    ; --------------------------------------------------------
    ; Static ping-pong pipes.
    ;
    ; Pipe A:
    ;   PID 1 fd 3 = write
    ;   PID 2 fd 3 = read
    ;
    ; Pipe B:
    ;   PID 2 fd 4 = write
    ;   PID 1 fd 4 = read
    ; --------------------------------------------------------

    lda USER_TASK_COUNT
    cmp #2
    bcc @done

    ; Pipe A: Task 1 -> Task 2
    lda #2          ; reader PID
    ldx #1          ; writer PID
    ldy #3          ; fd number in both processes
    jsr KERN_ENTRY_PIPE_CREATE_BETWEEN_FD
    bcc :+

@pipe_a_setup_failed:
    bra @pipe_a_setup_failed
:

    ; Pipe B: Task 2 -> Task 1
    lda #1          ; reader PID
    ldx #2          ; writer PID
    ldy #4          ; fd number in both processes
    jsr KERN_ENTRY_PIPE_CREATE_BETWEEN_FD
    bcc @done

@pipe_b_setup_failed:
    bra @pipe_b_setup_failed	
	
@done:
    clc
    rts

@bad_user_image:
    ; For now, trap hard. Later print a boot error.
    bra @bad_user_image
.endproc
