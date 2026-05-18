; ============================================================
; user_space.asm
; NEOX static user image
; ============================================================

.setcpu "65C02"

.segment "USER_TEXT"

.include "user_entry.asm"

.include "task1.asm"
.include "task2.asm"
.include "task3.asm"
