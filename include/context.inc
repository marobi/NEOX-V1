.ifndef __CONTEXT_INC__
__CONTEXT_INC__ = 1

; ------------------------------------------------------------
; MMU context slot states
; ------------------------------------------------------------
;
; These states describe kernel ownership of RP-created/preloaded
; MMU contexts.  They do not create contexts and they do not load
; images; RP/boot configuration still owns physical context setup.
;
; Current development configuration preloads neox_user.rom into
; contexts 1..9.  Keep MAX_CONTEXTS aligned with the RP-side
; configuration and monitor/debug_neox.cpp if mirrored there.
; ------------------------------------------------------------

MAX_CONTEXTS       = 10

CTX_INVALID        = $00    ; context does not exist / not usable
CTX_RESERVED       = $01    ; BIOS/kernel/monitor/supervisor-owned
CTX_PRELOADED_FREE = $02    ; resident neox_user image present and available
CTX_EMPTY_FREE     = $03    ; available, but no guaranteed resident image
CTX_IN_USE         = $04    ; owned by a process

.endif
