; ============================================================
; klog.inc
; NEOX - boot/init logging interface
;
; Model:
;   - BIOS_PUTCHAR-backed character output
;   - boot/init use only for now
;   - no FD/syscall/RP mailbox dependency
;   - uses dedicated zero page pointer klog_ptr
; ============================================================

.ifndef __KLOG_INC__
__KLOG_INC__ = 1

.importzp klog_ptr

.import klog_putc
.import klog_puts
.import klog_crlf
.import klog_clear
.import klog_boot
.import klog_ok
.import klog_fail

; ------------------------------------------------------------
; KLOG_LOAD msg
;
; Load klog_ptr with address of a zero-terminated string.
; ------------------------------------------------------------
.macro KLOG_LOAD msg
    lda #<msg
    sta klog_ptr
    lda #>msg
    sta klog_ptr+1
.endmacro

; ------------------------------------------------------------
; KLOG_PUTS msg
; ------------------------------------------------------------
.macro KLOG_PUTS msg
    KLOG_LOAD msg
    jsr klog_puts
.endmacro

; ------------------------------------------------------------
; KLOG_CLEAR
; ------------------------------------------------------------
.macro KLOG_CLEAR
    jsr klog_clear
.endmacro

; ------------------------------------------------------------
; KLOG_BOOT msg
; KLOG_OK msg
; KLOG_FAIL msg
; ------------------------------------------------------------
.macro KLOG_BOOT msg
    KLOG_LOAD msg
    jsr klog_boot
.endmacro

.macro KLOG_OK msg
    KLOG_LOAD msg
    jsr klog_ok
.endmacro

.macro KLOG_FAIL msg
    KLOG_LOAD msg
    jsr klog_fail
.endmacro

.endif
