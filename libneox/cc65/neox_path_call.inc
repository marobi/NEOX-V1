; ============================================================
; neox_path_call.inc
; Shared cc65 helper macro for one-path filesystem syscalls.
; ============================================================

.macro NEOX_DEFINE_ONE_PATH_CALL public_symbol, syscall_symbol, args_label
.export public_symbol

.segment "C_BSS"

args_label:
    .res 6

.segment "C_CODE"

.proc public_symbol
    sta args_label+0
    stx args_label+1

    lda #64
    sta args_label+2
    stz args_label+3

    stz args_label+4
    stz args_label+5

    sei
    ldx #<args_label
    ldy #>args_label
    jsr syscall_symbol
    bcs @failed

    lda #0
    tax
    rts

@failed:
    tya
    ldx #0
    rts
.endproc
.endmacro
