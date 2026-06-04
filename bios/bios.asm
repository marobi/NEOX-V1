; ********************************
; * BIOS RIEN MATTHIJSSE         *
; *        NEO6502_MMU           *
; * V3.0   APRIL 2026            *
; ********************************
;
	.SETCPU "65C02"
	
	.include "bios.inc"
	.include "syscall.inc" 
 
KBD_PORT   = $D000
DSP_PORT   = KBD_PORT + 1
CMD_PORT   = KBD_PORT + 2
PARAM_PORT = KBD_PORT + 3

; -----------------------------------------------------------------------------

; commands
CMD_NONE           = 0
CMD_ACK_IRQ        = 1
CMD_CONTEXT_SWITCH = 2

; -----------------------------------------------------------------------------
; set up origin
	.segment "BIOS"

BIOS:					; jump table (16 cmds)
	JMP _GETCHAR		; get char low level
	JMP _PUTCHAR		; put char low level
	JMP EMPTY			;
	JMP EMPTY			; 
	JMP SET_MMU_CONTEXT_AND_RTI	    ; switch context and rti
	JMP SET_MMU_CONTEXT_AND_JUMP	; switch context and jump
	JMP ACK_IRQ			; acknowledge IRQ
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot

; -----------------------------------------------------------------------------	

bios_jmp_vec:
	.res 2
	
; -----------------------------------------------------------------------------
; read a key from input, only a-reg is used
;
.proc _GETCHAR
@retry:
	lda KBD_PORT
	beq @retry
	stz KBD_PORT
	and #$7F
    clc
    rts
.endproc

; -----------------------------------------------------------------------------
; write a char to output, only a-reg is used
;
.proc _PUTCHAR
	pha
@busy:
	lda DSP_PORT
	bne @busy
	pla
	sta DSP_PORT
	clc
    rts
.endproc
	
; exec command  A=cmd, X=param (optional)
; wait for cmd == 0
; set new cmd
;
.proc exec_cmd
	pha

@wait_cmd:
	lda CMD_PORT
	bne @wait_cmd
	stx PARAM_PORT
	pla
	sta CMD_PORT
	
	rts
.endproc

;
; ack IRQ
; registers preserved
;
.proc ACK_IRQ
	pha
	stz BIOS_IRQ_SOURCE
	
@wait_ack:
	lda BIOS_IRQ_STATE
	bne @wait_ack
	pla
	rts
.endproc

;
; switch context
; A = context
;
.proc SET_MMU_CONTEXT_AND_RTI
	tax						; context
	sei
@wait_cmd:
	lda CMD_PORT
	bne @wait_cmd
	stx PARAM_PORT
	lda #CMD_CONTEXT_SWITCH
	sta CMD_PORT			; context switch

@wait_completion:
	lda CMD_PORT
	bne @wait_completion
	
	ply
	plx
	pla
	rti
.endproc

; A = context
; X = target low
; Y = target high
.proc SET_MMU_CONTEXT_AND_JUMP
	sei
    ; save jump target
    stx bios_jmp_vec
    sty bios_jmp_vec+1

	tax				; context
@wait_cmd:
	lda CMD_PORT
	bne @wait_cmd
	stx PARAM_PORT
	lda #CMD_CONTEXT_SWITCH
	sta CMD_PORT
@wait_completion:
	lda CMD_PORT
	bne @wait_completion

	cli
    jmp (bios_jmp_vec)
.endproc
	
; -----------------------------------------------------------------------------
; empty
;
.proc EMPTY
	BRK
	NOP
.endproc
