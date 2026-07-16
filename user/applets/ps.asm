; ============================================================
; ps.asm
; NEOX nbox applet: ps
; ============================================================

.setcpu "65C02"

.include "applets/common.inc"

.export nbox_cmd_ps
.export nbox_ps

NBOX_PROCINFO_PID   = 0
NBOX_PROCINFO_PPID  = 1
NBOX_PROCINFO_STATE = 2
NBOX_PROCINFO_WAIT  = 3
NBOX_PROCINFO_SIG   = 4
NBOX_PROCINFO_OBJ   = 5
NBOX_PROCINFO_HOLD  = 6

.segment "USER_DATA"

nbox_ps_pid:
    .byte 0

nbox_procinfo_buf:
    .res PROCINFO_RECORD_SIZE

nbox_procinfo_args:
    .byte 0
    .byte 0
    .word nbox_procinfo_buf
    .word PROCINFO_RECORD_SIZE

.segment "USER_TEXT"
nbox_msg_ps_header:
    .byte "PID PPID ST  WAIT OBJ HOLD SIG", 13
NBOX_MSG_PS_HEADER_LEN = * - nbox_msg_ps_header

nbox_ps_state_empty:
    .byte "EMP"
nbox_ps_state_new:
    .byte "NEW"
nbox_ps_state_ready:
    .byte "RDY"
nbox_ps_state_running:
    .byte "RUN"
nbox_ps_state_blocked:
    .byte "BLK"
nbox_ps_state_stopped:
    .byte "STP"
nbox_ps_state_zombie:
    .byte "ZOM"
nbox_ps_state_unknown:
    .byte "???"

nbox_ps_wait_none:
    .byte "----"
nbox_ps_wait_console:
    .byte "CON "
nbox_ps_wait_device:
    .byte "DEV "
nbox_ps_wait_pipe_read:
    .byte "PIPR"
nbox_ps_wait_timer:
    .byte "TIMR"
nbox_ps_wait_proc:
    .byte "PROC"
nbox_ps_wait_lock:
    .byte "LOCK"
nbox_ps_wait_pipe_write:
    .byte "PIPW"
nbox_ps_wait_rp:
    .byte "RP  "
nbox_ps_wait_unknown:
    .byte "????"


; ------------------------------------------------------------
nbox_ps_msg_fail:
    .byte "PS FAIL", 13
NBOX_PS_MSG_FAIL_LEN = * - nbox_ps_msg_fail

.proc nbox_print_ps_fail
    lda #<nbox_ps_msg_fail
    ldx #>nbox_ps_msg_fail
    ldy #NBOX_PS_MSG_FAIL_LEN
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_ps_print_state
    cmp #PROC_EMPTY
    beq @empty
    cmp #PROC_NEW
    beq @new
    cmp #PROC_READY
    beq @ready
    cmp #PROC_RUNNING
    beq @running
    cmp #PROC_BLOCKED
    beq @blocked
    cmp #PROC_STOPPED
    beq @stopped
    cmp #PROC_ZOMBIE
    beq @zombie
    lda #<nbox_ps_state_unknown
    ldx #>nbox_ps_state_unknown
    ldy #3
    jmp nbox_print_msg
@empty:
    lda #<nbox_ps_state_empty
    ldx #>nbox_ps_state_empty
    ldy #3
    jmp nbox_print_msg
@new:
    lda #<nbox_ps_state_new
    ldx #>nbox_ps_state_new
    ldy #3
    jmp nbox_print_msg
@ready:
    lda #<nbox_ps_state_ready
    ldx #>nbox_ps_state_ready
    ldy #3
    jmp nbox_print_msg
@running:
    lda #<nbox_ps_state_running
    ldx #>nbox_ps_state_running
    ldy #3
    jmp nbox_print_msg
@blocked:
    lda #<nbox_ps_state_blocked
    ldx #>nbox_ps_state_blocked
    ldy #3
    jmp nbox_print_msg
@stopped:
    lda #<nbox_ps_state_stopped
    ldx #>nbox_ps_state_stopped
    ldy #3
    jmp nbox_print_msg
@zombie:
    lda #<nbox_ps_state_zombie
    ldx #>nbox_ps_state_zombie
    ldy #3
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_ps_print_wait
    cmp #WAIT_NONE
    beq @none
    cmp #WAIT_CONSOLE
    beq @console
    cmp #WAIT_DEVICE
    beq @device
    cmp #WAIT_PIPE_READ
    beq @pipe_read
    cmp #WAIT_TIMER
    beq @timer
    cmp #WAIT_PROC
    beq @proc
    cmp #WAIT_LOCK
    beq @lock
    cmp #WAIT_PIPE_WRITE
    beq @pipe_write
    cmp #WAIT_RP
    beq @rp
    lda #<nbox_ps_wait_unknown
    ldx #>nbox_ps_wait_unknown
    ldy #4
    jmp nbox_print_msg
@none:
    lda #<nbox_ps_wait_none
    ldx #>nbox_ps_wait_none
    ldy #4
    jmp nbox_print_msg
@console:
    lda #<nbox_ps_wait_console
    ldx #>nbox_ps_wait_console
    ldy #4
    jmp nbox_print_msg
@device:
    lda #<nbox_ps_wait_device
    ldx #>nbox_ps_wait_device
    ldy #4
    jmp nbox_print_msg
@pipe_read:
    lda #<nbox_ps_wait_pipe_read
    ldx #>nbox_ps_wait_pipe_read
    ldy #4
    jmp nbox_print_msg
@timer:
    lda #<nbox_ps_wait_timer
    ldx #>nbox_ps_wait_timer
    ldy #4
    jmp nbox_print_msg
@proc:
    lda #<nbox_ps_wait_proc
    ldx #>nbox_ps_wait_proc
    ldy #4
    jmp nbox_print_msg
@lock:
    lda #<nbox_ps_wait_lock
    ldx #>nbox_ps_wait_lock
    ldy #4
    jmp nbox_print_msg
@pipe_write:
    lda #<nbox_ps_wait_pipe_write
    ldx #>nbox_ps_wait_pipe_write
    ldy #4
    jmp nbox_print_msg
@rp:
    lda #<nbox_ps_wait_rp
    ldx #>nbox_ps_wait_rp
    ldy #4
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
nbox_ps_obj_none:
    .byte "---"
nbox_ps_obj_file_io:
    .byte "FIO"
nbox_ps_obj_proc:
    .byte "PRC"
nbox_ps_obj_unknown:
    .byte "???"

.proc nbox_ps_print_object
    lda nbox_procinfo_buf + NBOX_PROCINFO_WAIT
    cmp #WAIT_NONE
    beq @none

    cmp #WAIT_LOCK
    bne @numeric

    lda nbox_procinfo_buf + NBOX_PROCINFO_OBJ
    cmp #LOCK_ID_FILE_IO
    beq @file_io
    cmp #LOCK_ID_PROC
    beq @proc

    lda #<nbox_ps_obj_unknown
    ldx #>nbox_ps_obj_unknown
    ldy #3
    jmp nbox_print_msg

@numeric:
    lda nbox_procinfo_buf + NBOX_PROCINFO_OBJ
    jsr nbox_print_hex_byte
    jmp nbox_print_space

@none:
    lda #<nbox_ps_obj_none
    ldx #>nbox_ps_obj_none
    ldy #3
    jmp nbox_print_msg

@file_io:
    lda #<nbox_ps_obj_file_io
    ldx #>nbox_ps_obj_file_io
    ldy #3
    jmp nbox_print_msg

@proc:
    lda #<nbox_ps_obj_proc
    ldx #>nbox_ps_obj_proc
    ldy #3
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
nbox_ps_hold_none:
    .byte "---"
nbox_ps_hold_file_io:
    .byte "FIO"
nbox_ps_hold_proc:
    .byte "PRC"
nbox_ps_hold_both:
    .byte "BTH"
nbox_ps_hold_unknown:
    .byte "???"

.proc nbox_ps_print_hold
    lda nbox_procinfo_buf + NBOX_PROCINFO_HOLD
    beq @none
    cmp #PROC_HOLD_FILE_IO
    beq @file_io
    cmp #PROC_HOLD_PROC
    beq @proc
    cmp #(PROC_HOLD_FILE_IO | PROC_HOLD_PROC)
    beq @both

    lda #<nbox_ps_hold_unknown
    ldx #>nbox_ps_hold_unknown
    ldy #3
    jmp nbox_print_msg

@none:
    lda #<nbox_ps_hold_none
    ldx #>nbox_ps_hold_none
    ldy #3
    jmp nbox_print_msg

@file_io:
    lda #<nbox_ps_hold_file_io
    ldx #>nbox_ps_hold_file_io
    ldy #3
    jmp nbox_print_msg

@proc:
    lda #<nbox_ps_hold_proc
    ldx #>nbox_ps_hold_proc
    ldy #3
    jmp nbox_print_msg

@both:
    lda #<nbox_ps_hold_both
    ldx #>nbox_ps_hold_both
    ldy #3
    jmp nbox_print_msg
.endproc

; ------------------------------------------------------------
.proc nbox_ps_print_row
    lda nbox_procinfo_buf + NBOX_PROCINFO_PID
    jsr nbox_print_hex_byte
    jsr nbox_print_space
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_PPID
    jsr nbox_print_hex_byte
    jsr nbox_print_space
    jsr nbox_print_space
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_STATE
    jsr nbox_ps_print_state
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_WAIT
    jsr nbox_ps_print_wait
    jsr nbox_print_space

    jsr nbox_ps_print_object
    jsr nbox_print_space

    jsr nbox_ps_print_hold
    jsr nbox_print_space
    jsr nbox_print_space

    lda nbox_procinfo_buf + NBOX_PROCINFO_SIG
    jsr nbox_print_hex_byte
    jmp nbox_print_cr
.endproc

; ------------------------------------------------------------
.proc nbox_ps
    lda #<nbox_msg_ps_header
    ldx #>nbox_msg_ps_header
    ldy #NBOX_MSG_PS_HEADER_LEN
    jsr nbox_print_msg

    stz nbox_ps_pid
@loop:
    lda nbox_ps_pid
    cmp #MAX_PROCS
    bcc @pid_ok
    clc
    rts

@pid_ok:
    sta nbox_procinfo_args + procinfo_args::pid
    SYSCALL nbox_procinfo_args, sys_getprocinfo
    bcc @info_ok
    jmp nbox_print_ps_fail

@info_ok:
    lda nbox_procinfo_buf + NBOX_PROCINFO_STATE
    cmp #PROC_EMPTY
    beq @next

    jsr nbox_ps_print_row

@next:
    inc nbox_ps_pid
    bra @loop
.endproc

; ------------------------------------------------------------
; nbox_ps
;
; Show a compact process table view.  Empty process slots are skipped.
.proc nbox_cmd_ps
    jmp nbox_ps
.endproc

