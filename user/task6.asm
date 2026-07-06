; ============================================================
; task6.asm
; NEOX - task 6 shell wrapper
;
; Purpose:
;   Task 6 is now only the process/task wrapper for the interactive
;   shell.  The actual prompt, VDU line input, command cleanup, and
;   nbox dispatch loop live in user/neosh.asm.
; ============================================================

.setcpu "65C02"

.export user_task6_entry

.import neosh_main

.segment "USER_TEXT"

.proc user_task6_entry
    jmp neosh_main
.endproc
