; ============================================================
; fd.asm
; NEOX - file descriptor / open object handling
;
; Model:
;   process fd table -> open object table -> backend device
;
; This file provides:
;   - global open-object initialization
;   - per-process fd initialization
;   - fd_attach primitive (core building block)
;
; Design rules:
;   - FD table is per-process
;   - open objects are system-wide and reference counted
;   - fd_attach is the only place that increments refcount
; ============================================================

.setcpu "65C02"

.include "scheduler_defs.inc"
.include "fd.inc"
.include "syscall.inc"

.export fd_init_tables
.export fd_init_process
.export fd_attach

.import proc_fd_obj
.import proc_fd_flags

.import open_type
.import open_refcnt
.import open_flags
.import open_dev

.importzp fd_ptr

.segment "KERN_TEXT"

; ------------------------------------------------------------
; fd_init_tables
;
; Purpose:
;   Initialize global open-object table.
;
; Behavior:
;   - clears all open-object slots
;   - installs three console objects:
;       0 = stdin
;       1 = stdout
;       2 = stderr
;
; Notes:
;   Refcounts start at 0 and are incremented when processes
;   attach descriptors.
; ------------------------------------------------------------

.proc fd_init_tables
    ldx #$00

@clear:
    stz open_type,x
    stz open_refcnt,x
    stz open_flags,x
    stz open_dev,x

    inx
    cpx #OPEN_MAX
    bne @clear

    ; stdin object
    lda #OBJ_DEVICE
    sta open_type+STDIN
    lda #DEV_CONSOLE
    sta open_dev+STDIN

    ; stdout object
    lda #OBJ_DEVICE
    sta open_type+STDOUT
    lda #DEV_CONSOLE
    sta open_dev+STDOUT

    ; stderr object
    lda #OBJ_DEVICE
    sta open_type+STDERR
    lda #DEV_CONSOLE
    sta open_dev+STDERR

    rts
.endproc

; ------------------------------------------------------------
; fd_attach
;
; Purpose:
;   Attach an FD to an open object for a given process.
;
; Input:
;   X = pid
;   Y = fd index
;   A = open object index
;
;   fd_flags_tmp must already be set by caller
;
; Behavior:
;   - stores object index in proc_fd_obj
;   - stores flags in proc_fd_flags
;   - increments open_refcnt
;
; Notes:
;   - no validation (caller must ensure fd is valid)
;   - no close of previous fd content (bootstrap usage)
; ------------------------------------------------------------

.importzp fd_flags_tmp

.proc fd_attach
    ; --------------------------------------------------------
    ; Compute base pointer for proc_fd_obj[pid][0]
    ; --------------------------------------------------------
    lda #<proc_fd_obj
    sta fd_ptr
    lda #>proc_fd_obj
    sta fd_ptr+1

    txa
    beq @obj_base_done
    tay

@obj_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @obj_base_loop

@obj_base_done:
    ; --------------------------------------------------------
    ; Store object index into fd slot
    ; --------------------------------------------------------
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; Compute base pointer for proc_fd_flags[pid][0]
    ; --------------------------------------------------------
    lda #<proc_fd_flags
    sta fd_ptr
    lda #>proc_fd_flags
    sta fd_ptr+1

    txa
    beq @flags_base_done
    tay

@flags_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @flags_base_loop

@flags_base_done:
    ; --------------------------------------------------------
    ; Store fd flags
    ; --------------------------------------------------------
    lda fd_flags_tmp
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; Increment open object refcount
    ; --------------------------------------------------------
    tax
    inc open_refcnt,x

    rts
.endproc

; ------------------------------------------------------------
; fd_init_process
;
; Purpose:
;   Initialize fd table for a new process.
;
; Input:
;   X = pid
;
; Behavior:
;   - clears fd table
;   - attaches:
;       fd 0 → stdin (READ)
;       fd 1 → stdout (WRITE)
;       fd 2 → stderr (WRITE)
;
; Notes:
;   Uses fd_attach to ensure consistent refcounting.
; ------------------------------------------------------------

.proc fd_init_process
    ; --------------------------------------------------------
    ; Clear proc_fd_obj[pid][*]
    ; --------------------------------------------------------
    lda #<proc_fd_obj
    sta fd_ptr
    lda #>proc_fd_obj
    sta fd_ptr+1

    txa
    beq @obj_base_done
    tay

@obj_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @obj_base_loop

@obj_base_done:
    ldy #0
    lda #FD_NONE

@clear_obj:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_obj

    ; --------------------------------------------------------
    ; Clear proc_fd_flags[pid][*]
    ; --------------------------------------------------------
    lda #<proc_fd_flags
    sta fd_ptr
    lda #>proc_fd_flags
    sta fd_ptr+1

    txa
    beq @flags_base_done
    tay

@flags_base_loop:
    clc
    lda fd_ptr
    adc #<MAX_FDS
    sta fd_ptr

    lda fd_ptr+1
    adc #>MAX_FDS
    sta fd_ptr+1

    dey
    bne @flags_base_loop

@flags_base_done:
    ldy #0
    lda #0

@clear_flags:
    sta (fd_ptr),y
    iny
    cpy #MAX_FDS
    bne @clear_flags

    ; --------------------------------------------------------
    ; Attach standard descriptors
    ; --------------------------------------------------------

    ; fd 0 → stdin (READ)
    lda #FD_FLAG_READ
    sta fd_flags_tmp
    ldy #STDIN
    lda #STDIN
    jsr fd_attach

    ; fd 1 → stdout (WRITE)
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDOUT
    lda #STDOUT
    jsr fd_attach

    ; fd 2 → stderr (WRITE)
    lda #FD_FLAG_WRITE
    sta fd_flags_tmp
    ldy #STDERR
    lda #STDERR
    jsr fd_attach

    rts
.endproc
