; ============================================================
; user/nbox/nbox_child.asm
; NEOX - resident nbox child syscall boundary
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "nbox/nbox.inc"

.export nbox_child_entry
.export _neosh_nbox_child_entry

.import _nbox_line_buf
.import _nbox_line_len
.import _nbox_execute_launch_id

.segment "USER_DATA"

nbox_child_get_line:
    .word _nbox_line_buf
    .byte NBOX_LINE_MAX
    .byte 0

.segment "USER_TEXT"

; <summary>
; Loads the opaque resident launch line into the C-owned nbox buffer.
; </summary>
; <returns>Carry clear on success; carry set on failure.</returns>
.proc nbox_load_child_line
    stz _nbox_line_buf
    stz _nbox_line_len

    SYSCALL nbox_child_get_line, sys_get_launch_line
    bcs @failed

    lda nbox_child_get_line + spawn_get_line_args::result_len
    sta _nbox_line_len
    clc
    rts

@failed:
    sec
    rts
.endproc

; <summary>
; Retrieves the launch selector and opaque argument line, calls the C nbox
; dispatcher, and exits with the applet status.
; </summary>
_neosh_nbox_child_entry = nbox_child_entry

.proc nbox_child_entry
    jsr sys_get_launch_id
    bcs @launch_failed

    pha
    jsr nbox_load_child_line
    bcs @line_failed

    pla
    jsr _nbox_execute_launch_id
    jmp sys_exit

@line_failed:
    pla

@launch_failed:
    lda #EINVAL
    jmp sys_exit
.endproc
