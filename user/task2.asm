; ============================================================
; task2.asm
; NEOX test task 2
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task2_entry

.segment "USER_TEXT"
	
.proc user_task2_entry
@loop:
    inc test_ctr2
    lda #$02
    sta test_turn

    lda #48
    jsr sys_sleep

    bra @loop
.endproc

.segment "USER_DATA"

test_ctr2:
	.res 1
test_turn:
	.res 1
