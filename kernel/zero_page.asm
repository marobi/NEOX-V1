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

.exportzp dev_ptr

.segment "ZEROPAGE"

proc_ptr:     .res 2

sc_ptr:       .res 2
sc_tmp:       .res 2

io_ptr:       .res 2
io_tmp:       .res 2

rp_tmp:       .res 2

sched_ptr:	  .res 2
sched_count:  .res 2

dev_ptr:      .res 2

; ============================================================
.exportzp fd_ptr
.exportzp fd_pid_tmp
.exportzp fd_index_tmp
.exportzp fd_obj_tmp
.exportzp fd_flags_tmp
.exportzp factor1
.exportzp factor2

fd_ptr:        .res 2
fd_pid_tmp:    .res 1
fd_index_tmp:  .res 1
fd_obj_tmp:    .res 1
fd_flags_tmp:  .res 1

factor1:       .res 1
factor2:       .res 1
