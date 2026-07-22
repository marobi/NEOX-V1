; ============================================================
; runtime.asm
; NEOX libneox - minimal cc65 runtime initialization
;
; Purpose:
;   Initializes the cc65 software stack and clears the C BSS before
;   any C function executes in the shell process.
;
; Provides:
;   neox_cc65_runtime_init
;
; Input:
;   None.
;
; Return:
;   None.
;
; Clobbers:
;   A, X, Y, ptr1, tmp1, tmp2.
;
; Notes:
;   - Constructors, destructors, initialized writable DATA, heap,
;     and standard cc65 startup are intentionally not supported.
;   - The software stack grows downward from $8000 into the reserved
;     $7C00-$7FFF C stack area.
; ============================================================

.setcpu "65C02"

.export neox_cc65_runtime_init

.importzp c_sp
.importzp ptr1
.importzp tmp1
.importzp tmp2

.import __C_STACK_START__
.import __C_STACK_SIZE__
.import __C_BSS_RUN__
.import __C_BSS_SIZE__

.segment "USER_TEXT"

; ------------------------------------------------------------
; neox_cc65_runtime_init
;
; Purpose:
;   Initializes the cc65 software-stack pointer and clears C BSS.
;
; Input:
;   None.
;
; Return:
;   None.
;
; Clobbers:
;   A, X, Y, ptr1, tmp1, tmp2.
; ------------------------------------------------------------
.proc neox_cc65_runtime_init
    lda #<(__C_STACK_START__ + __C_STACK_SIZE__)
    sta c_sp
    lda #>(__C_STACK_START__ + __C_STACK_SIZE__)
    sta c_sp+1

    lda #<__C_BSS_RUN__
    sta ptr1
    lda #>__C_BSS_RUN__
    sta ptr1+1

    lda #<__C_BSS_SIZE__
    sta tmp1
    lda #>__C_BSS_SIZE__
    sta tmp2

    lda tmp1
    ora tmp2
    beq @done

    lda #$00
    ldy #$00

@clear_byte:
    sta (ptr1),y

    inc ptr1
    bne @pointer_ready
    inc ptr1+1

@pointer_ready:
    lda tmp1
    bne @decrement_low
    dec tmp2

@decrement_low:
    dec tmp1

    lda tmp1
    ora tmp2
    bne @load_zero
    bra @done

@load_zero:
    lda #$00
    bra @clear_byte

@done:
    rts
.endproc
