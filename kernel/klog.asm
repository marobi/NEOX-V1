; ============================================================
; klog.asm
; NEOX - boot/init logging helper
;
; Scope:
;   Boot/init diagnostics only. This module deliberately avoids
;   syscalls, FD tables, FILE_IO, pipes, and RP mailbox requests.
;
; Backend:
;   BIOS_PUTCHAR, one character at a time.
;
; Rules:
;   - Do not call from IRQ handlers.
;   - Do not call from scheduler picker/wake paths.
;   - Do not call from gate/lock internals.
;   - Do not treat klog_ptr as generic scratch.
; ============================================================

.setcpu "65C02"

.include "bios.inc"

.export klog_putc
.export klog_puts
.export klog_crlf
.export klog_clear
.export klog_boot
.export klog_ok
.export klog_fail

.importzp klog_ptr

.segment "KERN_TEXT"

; ------------------------------------------------------------
; klog_putc
;
; Input:
;   A = character
;
; Output:
;   C clear on BIOS_PUTCHAR success
;
; Clobbers:
;   BIOS_PUTCHAR-defined
; ------------------------------------------------------------
.proc klog_putc
    jmp BIOS_PUTCHAR
.endproc

; ------------------------------------------------------------
; klog_crlf
;
; Output one NEOX console newline. The current VDU treats CR
; as line advance, so do not emit CR+LF here.
;
; Clobbers:
;   A
; ------------------------------------------------------------
.proc klog_crlf
    lda #$0D
    jmp klog_putc
.endproc

; ------------------------------------------------------------
; klog_clear
;
; Clear screen using the native NEOX VDU control code.
; The current VDU command table maps ^L / $0C to clear-screen.
; Do not emit ANSI/VT escape sequences here.
;
; Clobbers:
;   A
; ------------------------------------------------------------
.proc klog_clear
    lda #$0C        ; ^L / form feed / VDU clear screen
    jmp klog_putc
.endproc

; ------------------------------------------------------------
; klog_puts
;
; Input:
;   klog_ptr -> zero-terminated string
;
; Notes:
;   The pointer is advanced on page crossing. Boot log strings
;   are expected to be short, but page crossing is handled.
;
; Clobbers:
;   A, Y, klog_ptr high byte if string crosses a page
; ------------------------------------------------------------
.proc klog_puts
    ldy #$00

@loop:
    lda (klog_ptr),y
    beq @done

    jsr klog_putc

    iny
    bne @loop

    inc klog_ptr+1
    bra @loop

@done:
    rts
.endproc

; ------------------------------------------------------------
; klog_boot
;
; Input:
;   klog_ptr -> zero-terminated message
;
; Output:
;   [boot] <message><crlf>
; ------------------------------------------------------------
.proc klog_boot
    lda klog_ptr
    pha
    lda klog_ptr+1
    pha

    lda #<msg_boot_prefix
    sta klog_ptr
    lda #>msg_boot_prefix
    sta klog_ptr+1
    jsr klog_puts

    pla
    sta klog_ptr+1
    pla
    sta klog_ptr
    jsr klog_puts

    jmp klog_crlf
.endproc

; ------------------------------------------------------------
; klog_ok
;
; Input:
;   klog_ptr -> zero-terminated message
;
; Output:
;   [ ok ] <message><crlf>
; ------------------------------------------------------------
.proc klog_ok
    lda klog_ptr
    pha
    lda klog_ptr+1
    pha

    lda #<msg_ok_prefix
    sta klog_ptr
    lda #>msg_ok_prefix
    sta klog_ptr+1
    jsr klog_puts

    pla
    sta klog_ptr+1
    pla
    sta klog_ptr
    jsr klog_puts

    jmp klog_crlf
.endproc

; ------------------------------------------------------------
; klog_fail
;
; Input:
;   klog_ptr -> zero-terminated message
;
; Output:
;   [fail] <message><crlf>
; ------------------------------------------------------------
.proc klog_fail
    lda klog_ptr
    pha
    lda klog_ptr+1
    pha

    lda #<msg_fail_prefix
    sta klog_ptr
    lda #>msg_fail_prefix
    sta klog_ptr+1
    jsr klog_puts

    pla
    sta klog_ptr+1
    pla
    sta klog_ptr
    jsr klog_puts

    jmp klog_crlf
.endproc


msg_boot_prefix:
    .byte "[boot] ", $00

msg_ok_prefix:
    .byte "[ ok ] ", $00

msg_fail_prefix:
    .byte "[fail] ", $00
