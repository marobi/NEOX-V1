; ============================================================
; neox_get_launch_line.asm
; ============================================================

.setcpu "65C02"
.include "syscall.inc"

.export _neox_get_launch_line
.importzp c_sp
.importzp ptr1
.import incsp4

.segment "C_BSS"
neox_launch_line_args: .res SPAWN_GET_LINE_ARGS_SIZE
neox_launch_line_length_ptr: .res 2
neox_launch_line_status: .res 1

.segment "C_CODE"

; Stack: +0 size low, +1 size high, +2 buffer low, +3 buffer high.
.proc _neox_get_launch_line
    sta neox_launch_line_length_ptr
    stx neox_launch_line_length_ptr+1

    ldy #2
    lda (c_sp),y
    sta neox_launch_line_args+spawn_get_line_args::buffer_ptr
    iny
    lda (c_sp),y
    sta neox_launch_line_args+spawn_get_line_args::buffer_ptr+1

    ldy #0
    lda (c_sp),y
    sta neox_launch_line_args+spawn_get_line_args::buffer_size
    stz neox_launch_line_args+spawn_get_line_args::result_len

    sei
    ldx #<neox_launch_line_args
    ldy #>neox_launch_line_args
    jsr sys_get_launch_line
    bcs @failed

    stz neox_launch_line_status
    bra @store

@failed:
    tya
    sta neox_launch_line_status

@store:
    lda neox_launch_line_length_ptr
    ora neox_launch_line_length_ptr+1
    beq @return

    lda neox_launch_line_length_ptr
    sta ptr1
    lda neox_launch_line_length_ptr+1
    sta ptr1+1
    lda neox_launch_line_args+spawn_get_line_args::result_len
    sta (ptr1)
    ldy #1
    lda #0
    sta (ptr1),y

@return:
    lda neox_launch_line_status
    ldx #0
    jmp incsp4
.endproc
