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
	JMP _GETCHAR		; get char
	JMP _PUTCHAR		; put char
	JMP EMPTY			; check for char in available
	JMP EMPTY			; check for ^C input
	JMP SET_MMU_CONTEXT_AND_RTI	; switch context and rti
	JMP _GETLINE		; getline of chars
	JMP ACK_IRQ			; acknowledge IRQ
	JMP SET_MMU_CONTEXT_AND_JUMP	; switch context and jump
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot
	JMP EMPTY			; empty slot

; -----------------------------------------------------------------------------	
ocharbuf:
    .res 1
	
icharbuf:
	.res 1

read_blk:
    .byte STDIN
    .byte 0
    .word $0000				; ptr linebuf
    .word 1					; size linebuf

readc_blk:
    .byte STDIN
    .byte 0
    .word icharbuf
    .word 1

write_blk:
    .byte STDOUT
    .byte 0
    .word ocharbuf
    .word 1

bios_jmp_vec:
	.res 2
	
; -----------------------------------------------------------------------------
; read a key from input, only a-reg is used
;
.proc _GETCHAR
@retry:
    phx
    phy

@retry2:
    SYSCALL readc_blk, sys_read
    bcs @retry2		; likely EAGAIN

    ; A/X = bytes read.
    ; If zero bytes were returned, retry inside BIOS instead of
    ; returning NUL to the caller. This prevents user tasks from
    ; spinning on BEQ loops.
    ora #0
    bne @got_char

    txa
    bne @got_char

    bra @retry2

@got_char:
    lda icharbuf
    and #$7f

    stz icharbuf

    ply
    plx

    ora #0
    clc
    rts
.endproc

; -----------------------------------------------------------------------------
; write a char to output, only a-reg is used
;
.proc _PUTCHAR
	pha
	and #$7f			; standard ASCII
	beq @pc_ok
    sta ocharbuf

	phx
	phy
    SYSCALL write_blk, sys_write
	ply
	plx
    bcs @pc_error

@pc_ok:
	pla
	clc
    rts

@pc_error:
	pla
    sec
    rts
.endproc

; -----------------------------------------------------------------------------
; X = <linebuf
; Y = >linebuf
; A = len linebuf
; -----------------------------------------------------------------------------
.proc _GETLINE
	stx read_blk + rw_args::buf_ptr
	sty read_blk + rw_args::buf_ptr+1
	sta read_blk + rw_args::len
	stz read_blk + rw_args::len+1
	
	SYSCALL read_blk, sys_read
	bcs @gl_error
	
	clc
	rts
	
@gl_error:
	sec
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
	sei
	pha
	lda #CMD_ACK_IRQ
	jsr exec_cmd
	pla
	cli
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
	cli
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
