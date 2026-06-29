; ============================================================
; user_entry.asm
; NEOX static user image entry table
; ============================================================

.setcpu "65C02"

.export user_image_header

.segment "USER_ENTRY"

user_image_header:
    .byte "N", "X"         ; magic: NEOX User
    .byte $01              ; version
    .byte $04              ; number of boot tasks

    ; task 1
    .byte $01              ; context
    .byte $00              ; reserved/flags
    .word user_task1_entry

    ; task 2
    .byte $02
    .byte $00
    .word user_task2_entry

    ; task 3
    .byte $03
    .byte $00
    .word user_task3_entry


    ; task 4
    .byte $04
    .byte $00
    .word user_task4_entry

    ; terminator, optional
    .byte $ff
    .byte $00
    .word $0000
