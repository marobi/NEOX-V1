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
PROC_ZOMBIE     = $06
PROC_SETUP      = $07        ; allocated child, not runnable until spawn_commit

; ------------------------------------------------------------
; Flags byte bit definitions
; ------------------------------------------------------------

PROC_FLAG_NONE          = $00
PROC_FLAG_IDLE          = $01
PROC_FLAG_ATTACHED_CON  = $02

; ------------------------------------------------------------
; Process frame format
;
; All saved runnable process stacks use the IRQ-compatible
; extended RTI frame:
;     Y, X, A, P, PCL, PCH
; The scheduler has no per-process resume mode; normal task
; resume is always RTI.
; ------------------------------------------------------------

; ------------------------------------------------------------
; Process wait reasons
;
; WAIT_NONE means the process is not blocked on a known wait object.
; Other values describe why a PROC_BLOCKED process is blocked.
; ------------------------------------------------------------

WAIT_NONE       = $00
WAIT_CONSOLE    = $01
WAIT_DEVICE     = $02
WAIT_PIPE_READ  = $03        ; pipe read wait on empty pipe
WAIT_PIPE       = WAIT_PIPE_READ ; compatibility alias
WAIT_TIMER      = $04
WAIT_PROC       = $05

; Generic sleepable gate wait.
;
; wait_object identifies the gate object:
;   LOCK_ID_FILE_IO = FD/open-object/pipe/console syscall gate
;   LOCK_ID_PROC    = future process-management syscall gate
WAIT_LOCK       = $06

; Pipe write wait on a full pipe. Kept separate from WAIT_PIPE_READ so
; readers and writers can be woken by the correct readiness event.
WAIT_PIPE_WRITE = $07

; Blocked while retaining FILE_IO ownership until the RP2350 completes
; the single active generic filesystem request. wait_object contains the
; filesystem operation code.
WAIT_RP         = $08

LOCK_ID_FILE_IO = $00
LOCK_ID_PROC    = $01

; Diagnostic gate-hold mask returned by SYS_GETPROCINFO.
PROC_HOLD_NONE     = $00
PROC_HOLD_FILE_IO  = $01
PROC_HOLD_PROC     = $02

; Sentinel used for free gate owners and empty gate wait queues.
GATE_OWNER_NONE = $FF

EXIT_OK         = $00

.endif
