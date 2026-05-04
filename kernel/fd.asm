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

.include "fd.inc"
.include "math8.inc"
.include "scheduler_defs.inc"
.include "syscall.inc"

.export fd_init_tables
.export fd_init_process
.export fd_attach
.export fd_lookup

.import current_pid

.import proc_fd_obj
.import proc_fd_flags

.import open_type
.import open_refcnt
.import open_flags
.import open_dev

.importzp fd_ptr
.importzp fd_flags_tmp
.importzp fd_obj_tmp
.importzp fd_index_tmp
.importzp fd_pid_tmp

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
;   Attach one process FD slot to an existing open object.
;
; Input:
;   X = pid
;   Y = fd index
;   A = open object index
;   fd_flags_tmp = FD_FLAG_READ / FD_FLAG_WRITE / ...
;
; Output:
;   C clear = success
;
; Behavior:
;   proc_fd_obj[pid * MAX_FDS + fd]   = object index
;   proc_fd_flags[pid * MAX_FDS + fd] = fd flags
;   open_refcnt[object]++
;
; Notes:
;   - Caller must ensure fd is valid.
;   - Caller must ensure object is valid.
;   - Does not close an existing fd first.
;   - Uses mul8u:
;       factor1 = pid
;       factor2 = MAX_FDS
;       result low  = factor1
;       result high = factor2
; ------------------------------------------------------------

.proc fd_attach
    ; Preserve inputs because address calculation clobbers A/Y
    stx fd_pid_tmp
    sty fd_index_tmp
    sta fd_obj_tmp

    ; --------------------------------------------------------
    ; Calculate offset = pid * MAX_FDS
    ; --------------------------------------------------------
    txa
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    ; --------------------------------------------------------
    ; fd_ptr = proc_fd_obj + offset
    ; --------------------------------------------------------
    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ; Store open object index in fd object table
    ldy fd_index_tmp
    lda fd_obj_tmp
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; fd_ptr = proc_fd_flags + offset
    ; --------------------------------------------------------
    clc
    lda #<proc_fd_flags
    adc factor1
    sta fd_ptr

    lda #>proc_fd_flags
    adc factor2
    sta fd_ptr+1

    ; Store descriptor flags
    ldy fd_index_tmp
    lda fd_flags_tmp
    sta (fd_ptr),y

    ; --------------------------------------------------------
    ; Update open object refcount
    ; --------------------------------------------------------
    ldx fd_obj_tmp
    inc open_refcnt,x

    ; Restore useful caller-visible values
    ldx fd_pid_tmp
    ldy fd_index_tmp
    lda fd_obj_tmp

    clc
    rts
.endproc

; ------------------------------------------------------------
; fd_lookup
;
; Input:
;   A = fd
;
; Output:
;   C clear = success
;   X = open object index
;
;   C set = failure
;   Y = errno
;
; Clobbers:
;   A, X, Y, fd_ptr, fd_index_tmp, factor1, factor2
; ------------------------------------------------------------

.proc fd_lookup
    cmp #MAX_FDS
    bcc @fd_ok

    ldy #EBADF
    sec
    rts

@fd_ok:
    sta fd_index_tmp

    lda current_pid
    sta factor1

    lda #MAX_FDS
    sta factor2

    jsr mul8u

    clc
    lda #<proc_fd_obj
    adc factor1
    sta fd_ptr

    lda #>proc_fd_obj
    adc factor2
    sta fd_ptr+1

    ldy fd_index_tmp
    lda (fd_ptr),y
    cmp #FD_NONE
    bne @obj_ok

    ldy #EBADF
    sec
    rts

@obj_ok:
    tax
    clc
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
