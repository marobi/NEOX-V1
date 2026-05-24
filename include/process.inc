.ifndef __PROCESS_INC__
__PROCESS_INC__ = 1

; ------------------------------------------------------------
; Process states
; ------------------------------------------------------------

PROC_EMPTY      = $00
PROC_NEW        = $01
PROC_READY      = $02
PROC_RUNNING    = $03
PROC_BLOCKED    = $04
PROC_STOPPED    = $05

; ------------------------------------------------------------
; Flags byte bit definitions
; ------------------------------------------------------------

PROC_FLAG_NONE          = $00
PROC_FLAG_IDLE          = $01
PROC_FLAG_ATTACHED_CON  = $02

; ------------------------------------------------------------
; Process resume mode
;
; Defines how a saved process stack must be resumed.
; ------------------------------------------------------------

PROC_RESUME_RTI = $00
PROC_RESUME_RTS = $01

; ------------------------------------------------------------
; Process wait reasons
;
; WAIT_NONE means the process is not blocked on a known wait object.
; Other values describe why a PROC_BLOCKED process is blocked.
; ------------------------------------------------------------

WAIT_NONE       = $00
WAIT_CONSOLE    = $01
WAIT_DEVICE     = $02
WAIT_PIPE       = $03
WAIT_TIMER      = $04
WAIT_PROC       = $05

; Global read/write syscall serialization wait.
;
; Used when a process wants to enter ksys_read / ksys_write but
; another process already owns ksys_io_lock.
;
; wait_object = 0 for the current coarse global read/write lock.
WAIT_KSYS_IO	= $06

EXIT_OK			= $00

.endif