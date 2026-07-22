; ============================================================
; user/task/task6.asm
; NEOX - task 6 shell wrapper
;
; Purpose:
;   Minimal task-6 bootstrap. Initializes the process-private cc65
;   runtime and transfers control to the interactive shell.
;
; Policy:
;   Task 6 never uses BIOS/simple I/O. All userland I/O goes through
;   inherited descriptors and NEOX syscalls.
; ============================================================

.setcpu "65C02"

.export user_task6_entry

.import neosh_main
.import neox_cc65_runtime_init

.segment "USER_TEXT"

; ------------------------------------------------------------
; user_task6_entry
;
; Purpose:
;   Initializes the cc65 software stack and C BSS, then enters neosh.
;
; Input:
;   None.
;
; Return:
;   Does not return during normal shell execution.
; ------------------------------------------------------------
.proc user_task6_entry
    jsr neox_cc65_runtime_init
    jmp neosh_main
.endproc
