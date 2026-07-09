; ============================================================
; process_cwd.asm
; NEOX - process current-directory state
;
; Purpose:
;   Maintains the context-private cwd used by the filesystem resolver
;   and a shared per-process cwd mirror used for spawn inheritance.
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
.export proc_cwd_init_from_shared
.export proc_cwd_store_current_to_shared

.import active_pid
.import proc_cwd_shared_device
.import proc_cwd_shared_len
.import proc_cwd_shared_path

.importzp sched_ptr

.segment "BSS"

proc_cwd_device:
    .res 1

proc_cwd_len:
    .res 1

proc_cwd_path:
    .res NEOX_CWD_MAX

proc_cwd_offset_hi:
    .res 1

proc_cwd_copy_len:
    .res 1

.segment "KERN_TEXT"

; <summary>
; proc_cwd_set_shared_path_ptr sets sched_ptr to proc_cwd_shared_path[pid].
; </summary>
; <param name="A">PID.</param>
; <returns>sched_ptr points to the selected shared cwd path slot.</returns>
.proc proc_cwd_set_shared_path_ptr
    stz proc_cwd_offset_hi
    ; offset = pid * NEOX_CWD_MAX. Current NEOX_CWD_MAX is 32.
    asl
    rol proc_cwd_offset_hi
    asl
    rol proc_cwd_offset_hi
    asl
    rol proc_cwd_offset_hi
    asl
    rol proc_cwd_offset_hi
    asl
    rol proc_cwd_offset_hi

    clc
    adc #<proc_cwd_shared_path
    sta sched_ptr
    lda proc_cwd_offset_hi
    adc #>proc_cwd_shared_path
    sta sched_ptr+1
    rts
.endproc

; <summary>
; proc_cwd_init_current initializes the active process cwd to device 0 root
; and mirrors that value into shared per-process cwd state.
; </summary>
; <returns>C clear.</returns>
.proc proc_cwd_init_current
    stz proc_cwd_device
    stz proc_cwd_len
    stz proc_cwd_path
    jsr proc_cwd_store_current_to_shared
    clc
    rts
.endproc

; <summary>
; proc_cwd_store_current_to_shared mirrors the current context-private cwd
; into shared per-process cwd state for active_pid.
; </summary>
; <returns>C clear.</returns>
.proc proc_cwd_store_current_to_shared
    ldx active_pid
    lda proc_cwd_device
    sta proc_cwd_shared_device,x
    lda proc_cwd_len
    sta proc_cwd_shared_len,x
    sta proc_cwd_copy_len
    beq @done

    txa
    jsr proc_cwd_set_shared_path_ptr

    ldy #0
@copy:
    lda proc_cwd_path,y
    sta (sched_ptr),y
    iny
    cpy proc_cwd_copy_len
    bne @copy
    lda #0
    sta (sched_ptr),y
@done:
    clc
    rts
.endproc

; <summary>
; proc_cwd_init_from_shared initializes the current context-private cwd from
; the shared cwd mirror for active_pid. Boot tasks have an empty shared cwd,
; which means device 0 root.
; </summary>
; <returns>C clear.</returns>
.proc proc_cwd_init_from_shared
    ldx active_pid
    lda proc_cwd_shared_device,x
    sta proc_cwd_device

    lda proc_cwd_shared_len,x
    sta proc_cwd_len
    sta proc_cwd_copy_len
    beq @root

    txa
    jsr proc_cwd_set_shared_path_ptr

    ldy #0
@copy:
    lda (sched_ptr),y
    sta proc_cwd_path,y
    iny
    cpy proc_cwd_copy_len
    bne @copy
    lda #0
    sta proc_cwd_path,y
    clc
    rts

@root:
    stz proc_cwd_path
    clc
    rts
.endproc
