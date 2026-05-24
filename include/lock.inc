; ============================================================
; lock.inc
; NEOX - generic 65C02 lock primitives
; ============================================================
;
; Locks are byte variables.
; Bit 0 is the ownership bit.
;
; These are macros, not subroutines, because W65C02 TSB/TRB
; require a fixed memory operand.
;
; Rules:
;	- Do not hold short subsystem locks across sched_yield.
;	  ksys_io_lock is a sleepable serialization lock and may be held across 
;	  the complete read/write syscall path.
;   - Do not hold fd_lock across device read/write backends.
;   - Do not hold fd_lock across RP mailbox waits.
;   - Do not hold pipe_lock across blocking wait/yield.
;   - Use locks for subsystem ownership.
;   - Use php/sei/plp only for true IRQ-critical sections.
;
; Lock convention:
;   C set   = success / acquired / released
;   C clear = busy
;
; ============================================================

.ifndef __LOCK_INC__
__LOCK_INC__ = 1

LOCK_BIT = $01

; ------------------------------------------------------------
; LOCK_TRY_ACQUIRE lock
;
; Purpose:
;   Try to acquire lock bit 0.
;
; Output:
;   C set   = acquired
;   C clear = busy
;
; Clobbers:
;   A
; ------------------------------------------------------------

.macro LOCK_TRY_ACQUIRE lock
    lda #LOCK_BIT
    tsb lock
    beq :+
    clc
    bra :++
:
    sec
:
.endmacro

; ------------------------------------------------------------
; LOCK_ACQUIRE lock
;
; Purpose:
;   Spin until lock bit 0 is acquired.
;
; Output:
;   C set
;
; Clobbers:
;   A
;
; Notes:
;   This spins with IRQs enabled.
;   The lock holder must not block/yield while holding the lock.
; ------------------------------------------------------------

.macro LOCK_ACQUIRE lock
:
    lda #LOCK_BIT
    tsb lock
    beq :+
    bra :-
:
    sec
.endmacro

; ------------------------------------------------------------
; LOCK_RELEASE lock
;
; Purpose:
;   Release lock bit 0.
;
; Output:
;   C set
;
; Clobbers:
;   A
; ------------------------------------------------------------

.macro LOCK_RELEASE lock
    lda #LOCK_BIT
    trb lock
    sec
.endmacro

; ------------------------------------------------------------
; LOCK_IS_HELD lock
;
; Purpose:
;   Test whether lock bit 0 is held.
;
; Output:
;   Z set   = not held
;   Z clear = held
;
; Clobbers:
;   A
; ------------------------------------------------------------

.macro LOCK_IS_HELD lock
    lda lock
    and #LOCK_BIT
.endmacro

; ------------------------------------------------------------
; LOCK_ASSERT_FREE lock
;
; Purpose:
;   Debug trap if lock is already held.
;
; Notes:
;   This intentionally loops forever on failure.
; ------------------------------------------------------------

.macro LOCK_ASSERT_FREE lock
    lda lock
    and #LOCK_BIT
    beq :+
:
    bra :-
:
.endmacro

; ------------------------------------------------------------
; LOCK_ASSERT_HELD lock
;
; Purpose:
;   Debug trap if lock is not held.
;
; Notes:
;   This intentionally loops forever on failure.
; ------------------------------------------------------------

.macro LOCK_ASSERT_HELD lock
    lda lock
    and #LOCK_BIT
    bne :+
:
    bra :-
:
.endmacro

.endif
