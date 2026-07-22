; ============================================================
; user/shell/neosh_entry.asm
; NEOX - cc65 entry bridge for the C shell
; ============================================================

.setcpu "65C02"

.export neosh_main
.import _neosh_main

.segment "USER_TEXT"

; <summary>
; Transfers task-6 control to the cc65 C shell implementation.
; </summary>
.proc neosh_main
    jmp _neosh_main
.endproc
