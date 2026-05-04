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
.include "kernel.inc"

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

.proc k_read
	jmp KERN_ENTRY_KSYS_READ
.endproc

.proc k_write
	jmp KERN_ENTRY_KSYS_WRITE
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
