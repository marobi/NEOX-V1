; ============================================================
; zero_page.asm
; NEOX - per-context zero page storage
; ============================================================

.setcpu "65C02"

.segment "ZEROPAGE"

; ============================================================
.exportzp factor1
.exportzp factor2

factor1:        .res 1
factor2:        .res 1

; ============================================================
.exportzp proc_ptr
proc_ptr:     	.res 2

; ============================================================
.exportzp sc_ptr
.exportzp sc_tmp
sc_ptr:       	.res 2
sc_tmp:       	.res 2

; ============================================================
.exportzp io_ptr
.exportzp io_tmp
io_ptr:       	.res 2
io_tmp:       	.res 2

; ============================================================
.exportzp rp_tmp
rp_tmp:       	.res 2

; ============================================================
.exportzp sched_ptr
.exportzp sched_count
sched_ptr:	  	.res 2
sched_count:  	.res 2

; ============================================================

.exportzp dev_ptr
dev_ptr:      	.res 2

; ============================================================

.exportzp fd_ptr
fd_ptr:        .res 2

.exportzp pipe_ptr
.exportzp pipe_buf_ptr

pipe_ptr:       .res 2
pipe_buf_ptr:   .res 2
