; ============================================================
; task5.asm
; NEOX - RP filesystem write/readback syscall smoke test
;
; Purpose:
;   Exercises write-create-truncate support through the normal user
;   syscall path and validates it by reopening the same 8.3 file read-only.
;
; Behavior:
;   - open WRITE.TXT on RP filesystem device 0 with OPEN_WRITE_TRUNC
;   - write a fixed text buffer
;   - close
;   - reopen WRITE.TXT read-only
;   - read back up to 64 bytes
;   - print the readback bytes to STDOUT followed by CR
;   - exit after one pass
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task5_entry

T5_DEVICE          = 0
T5_READ_MAX        = 64
T5_FD_NONE        = $FF
T5_TEXT_LEN       = 24

.segment "USER_DATA"

t5_path:
    .byte "WRITE.TXT", 0

t5_write_text:
    .byte "This was written by NEOX"

t5_read_buf:
    .res T5_READ_MAX

t5_file_fd:
    .byte T5_FD_NONE

t5_msg_start:
    .byte "T5 FS WRITE START", 13

t5_msg_openw_fail:
    .byte "T5 OPENW FAIL", 13

t5_msg_write_fail:
    .byte "T5 WRITE FAIL", 13

t5_msg_openr_fail:
    .byte "T5 OPENR FAIL", 13

t5_msg_read_fail:
    .byte "T5 READ FAIL", 13

t5_msg_empty:
    .byte "T5 EMPTY", 13

t5_cr:
    .byte 13

t5_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t5_open_write_args:
    .word t5_path
    .word 64
    .byte OPEN_WRITE_TRUNC
    .byte T5_DEVICE

t5_open_read_args:
    .word t5_path
    .word 64
    .byte OPEN_READ
    .byte T5_DEVICE

t5_write_args:
    .byte T5_FD_NONE
    .byte 0
    .word t5_write_text
    .word T5_TEXT_LEN

t5_read_args:
    .byte T5_FD_NONE
    .byte 0
    .word t5_read_buf
    .word T5_READ_MAX

.segment "USER_TEXT"

; ------------------------------------------------------------
; t5_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = byte length including CR when present
; ------------------------------------------------------------

.proc t5_print_msg
    sta t5_stdout_args + rw_args::buf_ptr
    stx t5_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t5_stdout_args + rw_args::len
    stz t5_stdout_args + rw_args::len + 1

    SYSCALL t5_stdout_args, sys_write
    rts
.endproc

.proc t5_print_start
    lda #<t5_msg_start
    ldx #>t5_msg_start
    ldy #18
    jmp t5_print_msg
.endproc

.proc t5_print_openw_fail
    lda #<t5_msg_openw_fail
    ldx #>t5_msg_openw_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_write_fail
    lda #<t5_msg_write_fail
    ldx #>t5_msg_write_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_openr_fail
    lda #<t5_msg_openr_fail
    ldx #>t5_msg_openr_fail
    ldy #14
    jmp t5_print_msg
.endproc

.proc t5_print_read_fail
    lda #<t5_msg_read_fail
    ldx #>t5_msg_read_fail
    ldy #13
    jmp t5_print_msg
.endproc

.proc t5_print_empty
    lda #<t5_msg_empty
    ldx #>t5_msg_empty
    ldy #9
    jmp t5_print_msg
.endproc

; ------------------------------------------------------------
; t5_close_file
;
; Closes t5_file_fd if it contains an open descriptor.
; ------------------------------------------------------------

.proc t5_close_file
    lda t5_file_fd
    cmp #T5_FD_NONE
    beq @done

    pha
    lda #T5_FD_NONE
    sta t5_file_fd
    pla
    jsr sys_close

@done:
    rts
.endproc

; ------------------------------------------------------------
; t5_open_write_file
; ------------------------------------------------------------

.proc t5_open_write_file
    SYSCALL t5_open_write_args, sys_open
    bcc @ok

    sec
    rts

@ok:
    sta t5_file_fd
    sta t5_write_args + rw_args::fd
    clc
    rts
.endproc

; ------------------------------------------------------------
; t5_open_read_file
; ------------------------------------------------------------

.proc t5_open_read_file
    SYSCALL t5_open_read_args, sys_open
    bcc @ok

    sec
    rts

@ok:
    sta t5_file_fd
    sta t5_read_args + rw_args::fd
    clc
    rts
.endproc

; ------------------------------------------------------------
; t5_write_file
; ------------------------------------------------------------

.proc t5_write_file
    SYSCALL t5_write_args, sys_write
    bcs @fail

    cmp #T5_TEXT_LEN
    bne @fail
    cpx #0
    bne @fail

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; t5_read_file
; ------------------------------------------------------------

.proc t5_read_file
    SYSCALL t5_read_args, sys_read
    rts
.endproc

; ------------------------------------------------------------
; t5_print_readback
;
; Input:
;   A/X = byte count to write from t5_read_buf
; ------------------------------------------------------------

.proc t5_print_readback
    sta t5_stdout_args + rw_args::len
    stx t5_stdout_args + rw_args::len + 1

    ora t5_stdout_args + rw_args::len + 1
    bne @non_empty

    jsr t5_print_empty
    clc
    rts

@non_empty:
    lda #<t5_read_buf
    sta t5_stdout_args + rw_args::buf_ptr
    lda #>t5_read_buf
    sta t5_stdout_args + rw_args::buf_ptr + 1

    SYSCALL t5_stdout_args, sys_write
    bcs @fail

    lda #<t5_cr
    ldx #>t5_cr
    ldy #1
    jsr t5_print_msg

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; user_task5_entry
; ------------------------------------------------------------

.proc user_task5_entry
    jsr t5_print_start

    jsr t5_open_write_file
    bcc :+
    jsr t5_print_openw_fail
    jmp @exit
:
    jsr t5_write_file
    bcc :+
    jsr t5_print_write_fail
    jsr t5_close_file
    jmp @exit
:
    jsr t5_close_file

    jsr t5_open_read_file
    bcc :+
    jsr t5_print_openr_fail
    jmp @exit
:
    jsr t5_read_file
    bcc :+
    jsr t5_print_read_fail
    jsr t5_close_file
    jmp @exit
:
    jsr t5_print_readback
    jsr t5_close_file

@exit:
    jmp sys_exit
.endproc
