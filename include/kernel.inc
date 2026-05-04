; ============================================================
; kernel_entry.inc
; NEOX - fixed kernel entry table
; ============================================================

.ifndef __KERNEL_ENTRY_INC__
__KERNEL_ENTRY_INC__ = 1

KERNEL_BASE                 = $E000
KERNEL_ENTRY_SIZE           = 3

KERN_ENTRY_MAIN             = KERNEL_BASE + (0 * KERNEL_ENTRY_SIZE)
KERN_ENTRY_MONITOR_SYSCALL  = KERNEL_BASE + (1 * KERNEL_ENTRY_SIZE)
KERN_ENTRY_SET_BRK_VECTOR   = KERNEL_BASE + (2 * KERNEL_ENTRY_SIZE)
KERN_ENTRY_LEAVE_MONITOR    = KERNEL_BASE + (3 * KERNEL_ENTRY_SIZE)
KERN_ENTRY_KSYS_READ        = KERNEL_BASE + (4 * KERNEL_ENTRY_SIZE)
KERN_ENTRY_KSYS_WRITE       = KERNEL_BASE + (5 * KERNEL_ENTRY_SIZE)

.endif
