; ============================================================
; task4.asm
; NEOX - RP filesystem read-only syscall smoke test
;
; Purpose:
;   Exercises the new SYS_OPEN -> RP FS -> sys_read -> sys_close path
;   from a normal user task.
;
; Behavior:
;   - open TEST.TXT on RP filesystem device 0
;   - read up to 64 bytes
;   - write the bytes to STDOUT followed by CR
;   - print a short failure marker if open/read/write fails
;   - exit after one pass
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export user_task4_entry

T4_DEVICE          = 1
T4_READ_MAX        = 64
T4_FD_NONE        = $FF

.segment "USER_DATA"

t4_path:
    .byte "TEST.TXT", 0

t4_read_buf:
    .res T4_READ_MAX

t4_file_fd:
    .byte T4_FD_NONE

t4_msg_start:
    .byte "T4 FS START", 13

t4_msg_open_fail:
    .byte "T4 OPEN FAIL", 13

t4_msg_read_fail:
    .byte "T4 READ FAIL", 13

t4_msg_write_fail:
    .byte "T4 WRITE FAIL", 13

t4_msg_empty:
    .byte "T4 EMPTY", 13

t4_cr:
    .byte 13

t4_stdout_args:
    .byte STDOUT
    .byte 0
    .word 0
    .word 0

t4_open_args:
    .word t4_path
    .word 64
    .byte 0
    .byte T4_DEVICE

t4_read_args:
    .byte T4_FD_NONE
    .byte 0
    .word t4_read_buf
    .word T4_READ_MAX

.segment "USER_TEXT"

; ------------------------------------------------------------
; t4_print_msg
;
; Input:
;   A/X = string pointer
;   Y   = byte length including CR when present
; ------------------------------------------------------------

.proc t4_print_msg
    sta t4_stdout_args + rw_args::buf_ptr
    stx t4_stdout_args + rw_args::buf_ptr + 1

    tya
    sta t4_stdout_args + rw_args::len
    stz t4_stdout_args + rw_args::len + 1

    SYSCALL t4_stdout_args, sys_write
    rts
.endproc

.proc t4_print_start
    lda #<t4_msg_start
    ldx #>t4_msg_start
    ldy #12
    jmp t4_print_msg
.endproc

.proc t4_print_open_fail
    lda #<t4_msg_open_fail
    ldx #>t4_msg_open_fail
    ldy #13
    jmp t4_print_msg
.endproc

.proc t4_print_read_fail
    lda #<t4_msg_read_fail
    ldx #>t4_msg_read_fail
    ldy #13
    jmp t4_print_msg
.endproc

.proc t4_print_write_fail
    lda #<t4_msg_write_fail
    ldx #>t4_msg_write_fail
    ldy #14
    jmp t4_print_msg
.endproc

.proc t4_print_empty
    lda #<t4_msg_empty
    ldx #>t4_msg_empty
    ldy #9
    jmp t4_print_msg
.endproc

; ------------------------------------------------------------
; t4_close_file
;
; Closes t4_file_fd if it contains an open descriptor.
; ------------------------------------------------------------

.proc t4_close_file
    lda t4_file_fd
    cmp #T4_FD_NONE
    beq @done

    pha
    lda #T4_FD_NONE
    sta t4_file_fd
    pla
    jsr sys_close

@done:
    rts
.endproc

; ------------------------------------------------------------
; t4_open_file
;
; Return:
;   C clear = t4_file_fd contains the opened FD
;   C set   = open failed
; ------------------------------------------------------------

.proc t4_open_file
    SYSCALL t4_open_args, sys_open
    bcc @ok

    sec
    rts

@ok:
    sta t4_file_fd
    sta t4_read_args + rw_args::fd
    clc
    rts
.endproc

; ------------------------------------------------------------
; t4_read_file
;
; Return:
;   C clear = A/X contains bytes read
;   C set   = read failed
; ------------------------------------------------------------

.proc t4_read_file
    SYSCALL t4_read_args, sys_read
    rts
.endproc

; ------------------------------------------------------------
; t4_write_file_text
;
; Input:
;   A/X = byte count to write from t4_read_buf
;
; Return:
;   C clear = write succeeded
;   C set   = write failed or short transfer
; ------------------------------------------------------------

.proc t4_write_file_text
    sta t4_stdout_args + rw_args::len
    stx t4_stdout_args + rw_args::len + 1

    ora t4_stdout_args + rw_args::len + 1
    bne @non_empty

    jsr t4_print_empty
    clc
    rts

@non_empty:
    lda #<t4_read_buf
    sta t4_stdout_args + rw_args::buf_ptr
    lda #>t4_read_buf
    sta t4_stdout_args + rw_args::buf_ptr + 1

    SYSCALL t4_stdout_args, sys_write
    bcs @fail

    ; For the smoke test the read count is at most 64, so high byte is zero.
    cmp t4_stdout_args + rw_args::len
    bne @fail
    cpx t4_stdout_args + rw_args::len + 1
    bne @fail

    lda #<t4_cr
    ldx #>t4_cr
    ldy #1
    jsr t4_print_msg

    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; user_task4_entry
; ------------------------------------------------------------

.proc user_task4_entry
    jsr t4_print_start

    jsr t4_open_file
    bcc :+
    jsr t4_print_open_fail
    jmp @exit
:
    jsr t4_read_file
    bcc :+
    jsr t4_print_read_fail
    jsr t4_close_file
    jmp @exit
:
    jsr t4_write_file_text
    bcc :+
    jsr t4_print_write_fail
:
    jsr t4_close_file

@exit:
    jmp sys_exit
.endproc
