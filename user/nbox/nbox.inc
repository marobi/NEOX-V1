; ============================================================
; nbox.inc
; NEOX nbox shared applet constants
; ============================================================

NBOX_LINE_MAX      = 64
NBOX_PATH_MAX      = 64
NBOX_CMD_NAME_MAX  = 6
NBOX_CMD_NAME_SLOT = 7
NBOX_DIR_FD_NONE   = $FF
NBOX_FILE_FD_NONE  = $FF
NBOX_ATTR_DIR      = $10
NBOX_CAT_BUF_SIZE  = 64

; ------------------------------------------------------------
; Resident nbox applet launch ids
;
; These IDs are userland-defined selectors used by nbox_child_entry.
; The kernel stores and returns the selector, but does not interpret it.
; ------------------------------------------------------------

NBOX_APPLET_HELP    = $00
NBOX_APPLET_PWD     = $01
NBOX_APPLET_CD      = $02
NBOX_APPLET_LS      = $03
NBOX_APPLET_CAT     = $04
NBOX_APPLET_RM      = $05
NBOX_APPLET_MV      = $06
NBOX_APPLET_MKDIR   = $07
NBOX_APPLET_RMDIR   = $08
NBOX_APPLET_CP      = $09
NBOX_APPLET_PS      = $0A
NBOX_APPLET_ECHO    = $0B
NBOX_APPLET_KILL    = $0C
NBOX_APPLET_NONE    = $FF


; ------------------------------------------------------------
; nbox execution modes
;
; These modes describe where an applet must execute.  Parent mode is
; required for shell-state-changing commands such as CD.  Child mode is
; suitable for commands whose effects are on stdio/filesystem/process
; inspection and can run in a spawned resident nbox child.
; ------------------------------------------------------------

NBOX_EXEC_PARENT   = $00
NBOX_EXEC_CHILD    = $01
NBOX_EXEC_NONE     = $FE
NBOX_EXEC_UNKNOWN  = $FF
