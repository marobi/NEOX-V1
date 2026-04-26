; ============================================================
; test_write.asm
; NEOX - first syscall write test
; ca65
; ============================================================

.setcpu "65C02"

.include "syscall.inc"

.export _user_entry

.segment "RODATA"

msg:
    .byte "Hello from sys_write", $0D, $0A
msg_end:

MSG_LEN = msg_end - msg

write_blk:
    .byte STDOUT         ; rw_args::fd  = stdout
    .byte 0              ; rw_args::reserved
    .word msg            ; rw_args::buf_ptr
    .word MSG_LEN        ; rw_args::len

.segment "KERN_TEXT"

_user_entry:
    SYSCALL write_blk, sys_write
    bcs error

ok:
    brk

error:
    brk
