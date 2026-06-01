; ============================================================
; ksys_time.asm
; NEOX - kernel-side time/tick syscalls
; ============================================================

.setcpu "65C02"

.export ksys_ticks

.import system_ticks_lo
.import system_ticks_hi

.segment "KERN_TEXT"

; ------------------------------------------------------------
; ksys_ticks
;
; Return:
;   C clear
;   A = scheduler ticks low
;   X = scheduler ticks high
;
; Notes:
;   Uses a high-low-high stable read so an IRQ increment between
;   byte reads cannot return a torn 16-bit value.
; ------------------------------------------------------------

.proc ksys_ticks
@retry:
    ldx system_ticks_hi
    lda system_ticks_lo
    cpx system_ticks_hi
    bne @retry

    clc
    rts
.endproc
