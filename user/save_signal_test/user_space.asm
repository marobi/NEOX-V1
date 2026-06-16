; ============================================================
; user_space.asm
; NEOX static user image
;
; Temporary signal-test task set.
; Original freeze files are saved as user/*_freeze.asm.
; ============================================================

.setcpu "65C02"

.include "user_entry.asm"

.include "task1.asm"
.include "task2.asm"
.include "task3.asm"
