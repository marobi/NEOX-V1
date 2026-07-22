; ============================================================
; neox_rename.asm
; NEOX libneox - cc65 public neox_rename implementation
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _neox_rename

.importzp c_sp
.import incsp2

NEOX_RENAME_STACK_OLD_LO = 0
NEOX_RENAME_STACK_OLD_HI = 1
NEOX_RENAME_PATH_MAX = 64

.segment "C_BSS"

neox_rename_args:
    .res RENAME_ARGS_SIZE

.segment "C_CODE"

; ------------------------------------------------------------
; _neox_rename
;
; Input:
;   A/X       = new_path pointer
;   (c_sp)+0  = old_path low
;   (c_sp)+1  = old_path high
;
; Return:
;   A = NEOX status, X = 0.
; ------------------------------------------------------------
.proc _neox_rename
    sta neox_rename_args+rename_args::new_path_ptr
    stx neox_rename_args+rename_args::new_path_ptr+1

    ldy #NEOX_RENAME_STACK_OLD_LO
    lda (c_sp),y
    sta neox_rename_args+rename_args::old_path_ptr
    iny
    lda (c_sp),y
    sta neox_rename_args+rename_args::old_path_ptr+1

    lda #<NEOX_RENAME_PATH_MAX
    sta neox_rename_args+rename_args::max_len
    lda #>NEOX_RENAME_PATH_MAX
    sta neox_rename_args+rename_args::max_len+1

    stz neox_rename_args+rename_args::device
    stz neox_rename_args+rename_args::flags

    sei
    ldx #<neox_rename_args
    ldy #>neox_rename_args
    jsr sys_rename
    bcs @failed

    lda #0
    ldx #0
    jmp incsp2

@failed:
    tya
    ldx #0
    jmp incsp2
.endproc
