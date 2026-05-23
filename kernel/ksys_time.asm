; ============================================================
; ksys_time.asm
; NEOX - kernel-side time/tick syscalls
; ============================================================

.setcpu "65C02"

.export ksys_ticks

.import sched_ticks_lo
.import sched_ticks_hi

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
    ldx sched_ticks_hi
    lda sched_ticks_lo
    cpx sched_ticks_hi
    bne @retry

    clc
    rts
.endproc
