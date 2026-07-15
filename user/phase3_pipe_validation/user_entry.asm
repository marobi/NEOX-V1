; ============================================================
; user_entry.asm
; NEOX Phase 3 final pipe validation user image
;
; This validation image contains three tasks.
; Kernel tasks_init automatically wires:
;
;   PID 1 fd 3 -> PID 2 fd 3
;   PID 2 fd 4 -> PID 1 fd 4
; ============================================================

.setcpu "65C02"

.export user_image_header

.segment "USER_ENTRY"

user_image_header:
    .byte "N", "X"
    .byte $01
    .byte $03

    .byte $00
    .byte $00
    .word phase3_pipe_task1_entry

    .byte $00
    .byte $00
    .word phase3_pipe_task2_entry

    .byte $00
    .byte $00
    .word phase3_pipe_task3_entry

    .byte $FF
    .byte $00
    .word $0000
