; ============================================================
; irq.inc
; NEOX - IRQ / BRK interface
; ============================================================

.ifndef __IRQ_INC__
__IRQ_INC__ = 1

.import irq_init
.import irq_set_vector
.import irq_default
.import irq_entry
.import nmi_entry

.import irq_vecL
.import irq_vecH

.endif
