;
; BIOS jumptable + inline context switch primitive
;
.ifndef __BIOS_INC__
__BIOS_INC__ = 1

.include "config.inc"

BIOS_IO_PORT    =   IO_PAGE_BASE

BIOS_KBD_PORT   = BIOS_IO_PORT
BIOS_DSP_PORT   = BIOS_IO_PORT + 1
BIOS_CMD_PORT   = BIOS_IO_PORT + 2
BIOS_PARAM_PORT = BIOS_IO_PORT + 3

BIOS_IRQ_SOURCE =   RP_REQ_BASE + 16
BIOS_IRQ_STATE  =   RP_REQ_BASE + 19

; BIOS_BASE is defined by config.inc as $F000

BIOS_GETCHAR      = BIOS_BASE
BIOS_PUTCHAR      = BIOS_BASE+3

BIOS_ACK_IRQ      = BIOS_BASE+6

; BIOS command values used by the inline context switch macro.
BIOS_CMD_NONE           = 0
BIOS_CMD_ACK_IRQ        = 1
BIOS_CMD_CONTEXT_SWITCH = 2

; -----------------------------------------------------------------------------
; BIOS_CONTEXT_SWITCH
;
; Inline, stack-free MMU/private-context switch primitive.
;
; Input:
;   A = target context
;
; Effect:
;   Switches private memory / MMU context to A.
;
; Clobbers:
;   A, Y
;
; Preserves:
;   X
;
; Rules:
;   - macro only: no JSR/RTS may cross the context switch because the stack is
;     private per context.
;   - does not restore registers.
;   - does not RTI or JMP into a task.
;   - scheduler/context owner must perform TXS/RTI/JMP after this macro, when
;     the target context's private stack is mapped.
; -----------------------------------------------------------------------------
.macro BIOS_CONTEXT_SWITCH
    .local wait_cmd, wait_completion

    ; Preserve target context without using stack. X is intentionally left
    ; untouched so callers may carry the target SP across the switch.
    tay

wait_cmd:
    lda BIOS_CMD_PORT
    bne wait_cmd

    sty BIOS_PARAM_PORT
    lda #BIOS_CMD_CONTEXT_SWITCH
    sta BIOS_CMD_PORT

wait_completion:
    lda BIOS_CMD_PORT
    bne wait_completion
.endmacro

.endif
