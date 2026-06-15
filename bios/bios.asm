; ********************************
; * BIOS RIEN MATTHIJSSE         *
; *        NEO6502_MMU           *
; * V3.0   APRIL 2026            *
; ********************************
;
	.SETCPU "65C02"
	
	.include "bios.inc"
	.include "syscall.inc" 
 
; -----------------------------------------------------------------------------
; set up origin
	.segment "BIOS"

BIOS:					; jump table (16 cmds)
	JMP _GETCHAR		; get char low level
	JMP _PUTCHAR		; put char low level
	JMP ACK_IRQ			; acknowledge IRQ
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot

; -----------------------------------------------------------------------------
; simple interface: read a key from input, only a-reg is used
;
.proc _GETCHAR
@retry:
	lda BIOS_KBD_PORT
	beq @retry
	stz BIOS_KBD_PORT
	and #$7F
    clc
    rts
.endproc

; -----------------------------------------------------------------------------
; simple interface: write a char to output, only a-reg is used
;
.proc _PUTCHAR
	pha
@busy:
	lda BIOS_DSP_PORT
	bne @busy
	pla
	sta BIOS_DSP_PORT
	clc
    rts
.endproc
	
; exec command  A=cmd, X=param (optional)
; wait for cmd == 0
; set new cmd
;
;.proc exec_cmd
;	pha

;@wait_cmd:
;	lda BIOS_CMD_PORT
;	bne @wait_cmd
;	stx BIOS_PARAM_PORT
;	pla
;	sta BIOS_CMD_PORT
	
;	rts
;.endproc

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
	
; -----------------------------------------------------------------------------
; empty
;
.proc EMPTY
	BRK
	NOP
.endproc
