; ============================================================
; supervisor.inc
; NEOX - supervisor / monitor entry API
;
; Purpose:
;   Declares the kernel-internal routines used to enter and
;   leave supervisor context 0.
; ============================================================

.ifndef __SUPERVISOR_INC__
__SUPERVISOR_INC__ = 1

.import enter_monitor
.import leave_monitor

.endif
