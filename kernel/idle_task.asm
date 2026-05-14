.setcpu "65C02"

.segment "KERN_TEXT"

; ------------------------------------------------------------
; idle_loop
;
; Purpose:
;   Fallback execution path when no runnable user process exists.
;
; Notes:
;   Runs in PID 0 / context 0.
;   Timer IRQ continues to drive scheduling.
; ------------------------------------------------------------

.export idle_loop

.proc idle_loop
	cli			; assure IRQ enabled
@idle:
     bra @idle
.endproc
