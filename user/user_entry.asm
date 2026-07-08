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
    .byte $06              ; number of boot tasks

    ; task 1
    .byte $00              ; flags
    .byte $00              ; reserved
    .word user_task1_entry

    ; task 2
    .byte $00
    .byte $00
    .word user_task2_entry

    ; task 3
    .byte $00
    .byte $00
    .word user_task3_entry


    ; task 4
    .byte $00
    .byte $00
    .word user_task4_entry

    ; task 5
    .byte $00
    .byte $00
    .word user_task5_disabled_entry


    ; task 6
    .byte $00
    .byte $00
    .word user_task6_entry

    ; terminator, optional
    .byte $ff
    .byte $00
    .word $0000
