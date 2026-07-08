; ============================================================
; context.asm
; NEOX - MMU context slot ownership table
;
; Purpose:
;   Tracks kernel ownership of RP-created/preloaded MMU contexts.
;
; Model:
;   - The RP/boot configuration creates the physical contexts.
;   - The RP/boot configuration currently preloads neox_user.rom
;     into contexts 1..9.
;   - NEOX tracks which context slots are reserved, free, or in use.
;   - This module does not create contexts and does not load images.
;
; Concurrency:
;   - ctx_init_table is called during kernel bootstrap.
;   - allocation/free helpers are process-lifecycle helpers and
;     must be called while the PROC gate is held, or before scheduling
;     starts during bootstrap.
; ============================================================

.setcpu "65C02"

.include "context.inc"

.export ctx_init_table
.export ctx_find_free_preloaded
.export ctx_alloc_preloaded_for_pid
.export ctx_free_for_pid

.import context_state
.import context_owner_pid

.segment "KERN_BSS"

ctx_tmp_pid:
    .res 1


.segment "KERN_TEXT"

; ------------------------------------------------------------
; ctx_init_table
;
; Purpose:
;   Initialize kernel-owned context slot state for the current RP
;   preload model.
;
; Policy:
;   - Context 0 is reserved for supervisor/BIOS/monitor/kernel use.
;   - Contexts 1..MAX_CONTEXTS-1 are assumed to contain the
;     preloaded resident neox_user image and start as
;     CTX_PRELOADED_FREE.
;
; Return:
;   C clear
;
; Clobbers:
;   A, X
; ------------------------------------------------------------

.proc ctx_init_table
    ldx #$00

@clear_all:
    lda #CTX_INVALID
    sta context_state,x

    lda #$FF
    sta context_owner_pid,x

    inx
    cpx #MAX_CONTEXTS
    bne @clear_all

    lda #CTX_RESERVED
    sta context_state

    lda #$FF
    sta context_owner_pid

    ldx #$01

@mark_preloaded:
    cpx #MAX_CONTEXTS
    beq @done

    lda #CTX_PRELOADED_FREE
    sta context_state,x

    lda #$FF
    sta context_owner_pid,x

    inx
    bra @mark_preloaded

@done:
    clc
    rts
.endproc

; ------------------------------------------------------------
; ctx_find_free_preloaded
;
; Purpose:
;   Find a free context containing the resident preloaded user image.
;
; Return:
;   C clear = found, A = context id
;   C set   = no preloaded free context available
;
; Clobbers:
;   A, X
; ------------------------------------------------------------

.proc ctx_find_free_preloaded
    ldx #$01

@scan:
    cpx #MAX_CONTEXTS
    beq @fail

    lda context_state,x
    cmp #CTX_PRELOADED_FREE
    beq @found

    inx
    bra @scan

@found:
    txa
    clc
    rts

@fail:
    sec
    rts
.endproc

; ------------------------------------------------------------
; ctx_alloc_preloaded_for_pid
;
; Purpose:
;   Allocate a free preloaded context for a process.
;
; Uses:
;   - static boot task creation
;   - future resident nbox child spawn
;
; Inputs:
;   X = owning PID
;
; Return:
;   C clear = allocated
;             A = context id
;             X = owning PID
;   C set   = no CTX_PRELOADED_FREE context available
;             X = owning PID
;
; Clobbers:
;   A
; ------------------------------------------------------------

.proc ctx_alloc_preloaded_for_pid
    stx ctx_tmp_pid
    ldx #$01

@scan:
    cpx #MAX_CONTEXTS
    beq @fail

    lda context_state,x
    cmp #CTX_PRELOADED_FREE
    beq @found

    inx
    bra @scan

@found:
    lda #CTX_IN_USE
    sta context_state,x

    lda ctx_tmp_pid
    sta context_owner_pid,x

    txa
    ldx ctx_tmp_pid
    clc
    rts

@fail:
    ldx ctx_tmp_pid
    sec
    rts
.endproc

; ------------------------------------------------------------
; ctx_free_for_pid
;
; Purpose:
;   Release the context owned by a terminating process.
;
; Inputs:
;   X = PID
;
; Return:
;   C clear = context released
;             X = PID
;   C set   = no owned context found
;             X = PID
;
; Current policy:
;   Released contexts return to CTX_PRELOADED_FREE because the current
;   implementation only runs resident/preloaded neox_user images.
;
; Future external executable loading:
;   Once a process can overwrite a context with an external program,
;   process metadata must distinguish resident-image contexts from
;   externally loaded images.  External-image contexts must be released
;   as CTX_EMPTY_FREE unless the resident image is restored.
;
; Clobbers:
;   A
; ------------------------------------------------------------

.proc ctx_free_for_pid
    stx ctx_tmp_pid
    ldx #$01

@scan:
    cpx #MAX_CONTEXTS
    beq @not_found

    lda context_owner_pid,x
    cmp ctx_tmp_pid
    bne @next

    lda context_state,x
    cmp #CTX_IN_USE
    bne @next

    lda #CTX_PRELOADED_FREE
    sta context_state,x

    lda #$FF
    sta context_owner_pid,x

    ldx ctx_tmp_pid
    clc
    rts

@next:
    inx
    bra @scan

@not_found:
    ldx ctx_tmp_pid
    sec
    rts
.endproc
