; ============================================================
; syscall_table.asm
; NEOX - syscall jump table and kernel-side syscall handlers
;
; Purpose:
;   Defines the fixed syscall jump table in shared syscall page C
;   and implements the kernel-side handlers for currently
;   supported syscalls.
;
; Design:
;   - Syscall stubs live at SYSCALL_BASE ($C000)
;   - Each entry is a 3-byte JMP
;   - User code calls fixed entry addresses
;   - Handlers run in shared syscall code
;
; Current implemented syscalls:
;   read     -> console input via RP2350 mailbox
;   write    -> console output via RP2350 mailbox
;   monitor  -> explicit transfer to supervisor/MICMON
;
; I/O pointer policy:
;   - io_ptr is used by the syscall/RP console path
;   - read/write fully decode the argument block first
;   - only after that is io_ptr repointed to the caller buffer
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "mailbox.inc"
.include "kernel_entry.inc"

.export syscall_table
.export k_exit
.export k_open
.export k_close
.export k_read
.export k_write
.export k_monitor
.export k_exec
.export k_wait
.export k_chdir
.export k_stat
.export k_pipe
.export k_yield
.export k_sbrk
.export k_ioctl

.import rp_console_write
.import rp_console_read
.import current_pid
.import console_owner_pid

.importzp io_ptr
.importzp io_tmp


.segment "SYSCALL_STUBS"

.assert * = SYSCALL_BASE, error, "SYSCALL_STUBS must start at SYSCALL_BASE"

; ------------------------------------------------------------
; syscall_table
;
; Entry index must match syscall number exactly:
;   0  -> k_exit
;   1  -> k_open
;   2  -> k_close
;   3  -> k_read
;   4  -> k_write
;   5  -> k_monitor
;   6  -> k_exec
;   7  -> k_wait
;   8  -> k_chdir
;   9  -> k_stat
;   10 -> k_pipe
;   11 -> k_yield
;   12 -> k_sbrk
;   13 -> k_ioctl
; ------------------------------------------------------------

syscall_table:
    jmp k_exit
    jmp k_open
    jmp k_close
    jmp k_read
    jmp k_write
    jmp k_monitor
    jmp k_exec
    jmp k_wait
    jmp k_chdir
    jmp k_stat
    jmp k_pipe
    jmp k_yield
    jmp k_sbrk
    jmp k_ioctl

.segment "KERN_TEXT"

; ------------------------------------------------------------
; sys_ok_ax0
;
; Return:
;   C clear
;   A = 0
;   X = 0
; ------------------------------------------------------------

.proc sys_ok_ax0
    lda #0
    tax
    clc
    rts
.endproc

; ------------------------------------------------------------
; sys_err_inval
;
; Return:
;   C set
;   Y = EINVAL
; ------------------------------------------------------------

.proc sys_err_inval
    ldy #EINVAL
    sec
    rts
.endproc

; ------------------------------------------------------------
; sys_err_enoent
;
; Return:
;   C set
;   Y = 2
; ------------------------------------------------------------

.proc sys_err_enoent
    ldy #2
    sec
    rts
.endproc

; ------------------------------------------------------------
; sys_err_eio
;
; Return:
;   C set
;   Y = EIO
; ------------------------------------------------------------

.proc sys_err_eio
    ldy #EIO
    sec
    rts
.endproc

; ------------------------------------------------------------
; sys_err_enomem
;
; Return:
;   C set
;   Y = 4
; ------------------------------------------------------------

.proc sys_err_enomem
    ldy #4
    sec
    rts
.endproc

.proc k_exit
    ldy #EINVAL
    sec
    rts
.endproc

.proc k_open
    ldy #2
    sec
    rts
.endproc

.proc k_close
    jmp sys_ok_ax0
.endproc

; ------------------------------------------------------------
; k_read
;
; Calling convention:
;   X/Y -> rw_args block
;
; Supported fds:
;   STDIN only
;
; Behavior:
;   - validates fd
;   - enforces console ownership
;   - decodes buf_ptr and len from rw_args
;   - only after full decode repoints io_ptr to caller buffer
;   - tail-calls RP console read transport
;
; Ownership policy:
;   - only console_owner_pid may consume STDIN
;   - non-owner sees "nothing available" for now
; ------------------------------------------------------------

.proc k_read
    ; Save pointer to argument block
    stx io_ptr
    sty io_ptr+1

    ; Validate file descriptor
    ldy #rw_args::fd
    lda (io_ptr),y
    cmp #STDIN
    beq @stdin
    jmp sys_err_inval

@stdin:
	lda RP_CONSOLE_PID
	sta console_owner_pid
	
    ; Enforce console ownership
    cmp current_pid
    beq @decode_args
    jmp sys_ok_ax0

@decode_args:
    ; Read caller buffer pointer from argument block
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Read requested length while io_ptr still points at args
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; Now repoint io_ptr to the caller buffer
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte and tail-call transport
    pla
    jmp rp_console_read
.endproc

; ------------------------------------------------------------
; k_write
;
; Calling convention:
;   X/Y -> rw_args block
;
; Supported fds:
;   STDOUT, STDERR
;
; Behavior:
;   - validates fd
;   - decodes buf_ptr and len from rw_args
;   - only after full decode repoints io_ptr to caller buffer
;   - tail-calls RP console write transport
; ------------------------------------------------------------

.proc k_write
    ; Save pointer to argument block
    stx io_ptr
    sty io_ptr+1

    ; Validate file descriptor
    ldy #rw_args::fd
    lda (io_ptr),y
    cmp #STDOUT
    beq @decode_args
    cmp #STDERR
    beq @decode_args
    jmp sys_err_inval

@decode_args:
    ; Read caller buffer pointer from argument block
    ldy #rw_args::buf_ptr
    lda (io_ptr),y
    sta io_tmp
    iny
    lda (io_ptr),y
    sta io_tmp+1

    ; Read requested length while io_ptr still points at args
    ldy #rw_args::len
    lda (io_ptr),y
    pha
    iny
    lda (io_ptr),y
    tax

    ; Now repoint io_ptr to the caller buffer
    lda io_tmp
    sta io_ptr
    lda io_tmp+1
    sta io_ptr+1

    ; Restore low length byte and tail-call transport
    pla
    jmp rp_console_write
.endproc

; ------------------------------------------------------------
; k_monitor
;
; Explicit transfer to supervisor/MICMON.
; This does not return through the syscall layer directly.
; ------------------------------------------------------------

.proc k_monitor
    jmp KERN_ENTRY_MONITOR_SYSCALL
.endproc

.proc k_exec
    ldy #2
    sec
    rts
.endproc

.proc k_wait
    ldy #EINVAL
    sec
    rts
.endproc

.proc k_chdir
    ldy #2
    sec
    rts
.endproc

.proc k_stat
    ldy #2
    sec
    rts
.endproc

.proc k_pipe
    ldy #4
    sec
    rts
.endproc

.proc k_yield
    clc
    rts
.endproc

.proc k_sbrk
    ldy #4
    sec
    rts
.endproc

.proc k_ioctl
    ldy #EINVAL
    sec
    rts
.endproc
