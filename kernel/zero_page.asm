; ============================================================
; zero_page.asm
; NEOX - per-context zero page storage
; ============================================================

.setcpu "65C02"

.segment "ZEROPAGE"

; ============================================================
.exportzp factor1
.exportzp factor2

; Context-private arithmetic scratch.
; IRQ handlers must not use these locations while an interrupted
; context may be executing mul8u.
factor1:        .res 1
factor2:        .res 1

; ============================================================
.exportzp io_ptr
io_ptr:         .res 2

; ============================================================
.exportzp sched_ptr
sched_ptr:      .res 2

; ============================================================
.exportzp dev_ptr
dev_ptr:        .res 2

; ============================================================
.exportzp fd_ptr
fd_ptr:         .res 2

; ============================================================
.exportzp pipe_ptr
.exportzp pipe_buf_ptr

pipe_ptr:       .res 2
pipe_buf_ptr:   .res 2

; ============================================================
.exportzp klog_ptr
klog_ptr:      .res 2
