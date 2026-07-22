; ============================================================
; neox_mkdir.asm
; NEOX libneox - cc65 one-path filesystem wrapper
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "neox_path_call.inc"

NEOX_DEFINE_ONE_PATH_CALL _neox_mkdir, sys_mkdir, neox_mkdir_args
