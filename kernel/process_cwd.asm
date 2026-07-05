; ============================================================
; process_cwd.asm
; NEOX - process-private current-directory state
;
; Purpose:
;   Owns V36 current-directory storage. This is private to the
;   currently mapped process/context private RAM. It is deliberately
;   not part of shared_state.asm and is not mirrored by the RP debug
;   shared-state structure.
;
; Model:
;   proc_cwd_device = current filesystem device, 0..3
;   proc_cwd_len    = current path length, excluding root
;   proc_cwd_path   = current path component bytes without leading slash
;
; Root is represented internally as length 0. getcwd renders it as D:/.
; ============================================================

.setcpu "65C02"

.include "config.inc"

.export proc_cwd_device
.export proc_cwd_len
.export proc_cwd_path
.export proc_cwd_init_current

.segment "BSS"

proc_cwd_device:
    .res 1

proc_cwd_len:
    .res 1

proc_cwd_path:
    .res NEOX_CWD_MAX


.segment "KERN_TEXT"

; <summary>
; proc_cwd_init_current initializes the current process/private cwd state.
; Default cwd is device 0 root, rendered as 0:/.
; </summary>
; <returns>C clear.</returns>
.proc proc_cwd_init_current
    stz proc_cwd_device
    stz proc_cwd_len
    stz proc_cwd_path
    clc
    rts
.endproc
