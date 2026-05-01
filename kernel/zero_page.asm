; ============================================================
; zero_page.asm
; NEOX - per-context zero page storage
; ============================================================

.setcpu "65C02"

.exportzp proc_ptr

.exportzp sc_ptr
.exportzp sc_tmp

.exportzp io_ptr
.exportzp io_tmp

.exportzp rp_tmp

.exportzp sched_ptr
.exportzp sched_count

.exportzp fd_ptr
.exportzp fd_flags_tmp

.segment "ZEROPAGE"

proc_ptr:     .res 2

sc_ptr:       .res 2
sc_tmp:       .res 2

io_ptr:       .res 2
io_tmp:       .res 2

rp_tmp:       .res 2

sched_ptr:	  .res 2
sched_count:  .res 2

fd_ptr:        .res 2
fd_flags_tmp:  .res 1