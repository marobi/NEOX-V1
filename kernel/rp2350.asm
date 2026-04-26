; ============================================================
; rp2350.asm
; NEOX - RP2350 request helper routines
;
; Purpose:
;   Provides the kernel-side transport layer used to communicate
;   with the RP2350 co-processor through a shared request/result
;   block and MMIO control registers.
;
; Architecture:
;   - Request/result block lives in shared RAM
;   - Doorbell / status registers live in shared I/O page
;   - Mailbox is a global system resource
;   - All contexts see the same mailbox control registers
;
; Synchronization model:
;   - rp_lock serializes mailbox ownership
;   - sched_lock prevents timer-IRQ preemption during a live
;     mailbox transaction
;
; Design rule:
;   This file is a transport/mechanism layer only.
;   It does NOT implement scheduler policy.
; ============================================================

.setcpu "65C02"

.include "bios.inc"
.include "mailbox.inc"
.include "syscall.inc"

.export rp_try_acquire_lock
.export rp_acquire_lock
.export rp_release_lock
.export rp_wait_idle
.export rp_wait_done
.export rp_console_write
.export rp_console_read

.importzp io_ptr
.importzp rp_tmp

.import rp_lock
.import sched_lock_enter
.import sched_lock_leave

.segment "KERN_TEXT"

; ------------------------------------------------------------
; rp_try_acquire_lock
;
; Purpose:
;   Attempt to acquire exclusive ownership of the shared RP2350
;   mailbox interface.
;
; Inputs:
;   None.
;
; Outputs:
;   C = 1  lock acquired
;   C = 0  mailbox already owned
;
; Clobbers:
;   A
;
; Notes:
;   Uses bit 0 of rp_lock as the mailbox ownership bit.
; ------------------------------------------------------------

.proc rp_try_acquire_lock
    lda #$01
    tsb rp_lock
    beq @acquired

    clc
    rts

@acquired:
    sec
    rts
.endproc

; ------------------------------------------------------------
; rp_acquire_lock
;
; Purpose:
;   Spin until mailbox ownership is acquired.
;
; Inputs:
;   None.
;
; Outputs:
;   C = 1 on return
;
; Clobbers:
;   A
;
; Notes:
;   Busy-waiting is acceptable here because this is the low-level
;   kernel transport path and mailbox transactions are expected to
;   be short.
; ------------------------------------------------------------

.proc rp_acquire_lock
@wait:
    jsr rp_try_acquire_lock
    bcc @wait
    rts
.endproc

; ------------------------------------------------------------
; rp_release_lock
;
; Purpose:
;   Release mailbox ownership.
;
; Inputs:
;   None.
;
; Outputs:
;   C = 1
;
; Clobbers:
;   A
; ------------------------------------------------------------

.proc rp_release_lock
    lda #$01
    trb rp_lock
    sec
    rts
.endproc

; ------------------------------------------------------------
; rp_wait_idle
;
; Purpose:
;   Wait until RP_STATUS reports the interface as idle.
;
; Inputs:
;   None.
;
; Outputs:
;   C = 0 on success
;
; Clobbers:
;   A
; ------------------------------------------------------------

.proc rp_wait_idle
@loop:
    lda RP_STATUS
    cmp #RP_IDLE
    bne @loop

    clc
    rts
.endproc

; ------------------------------------------------------------
; rp_wait_done
;
; Purpose:
;   Wait until RP_STATUS reports completion or failure.
;
; Inputs:
;   None.
;
; Outputs:
;   C = 0  operation completed successfully
;   C = 1  operation failed
;   Y      = RP_ERR on failure
;
; Clobbers:
;   A
; ------------------------------------------------------------

.proc rp_wait_done
@loop:
    lda RP_STATUS
    cmp #RP_DONE
    beq @done
    cmp #RP_ERROR
    beq @error
    bra @loop

@done:
    clc
    rts

@error:
    ldy RP_ERR
    sec
    rts
.endproc

; ------------------------------------------------------------
; rp_console_write
;
; Purpose:
;   Submit a console write request to the RP2350.
;
; Inputs:
;   ptr0 -> source buffer
;   A    = length low byte
;   X    = length high byte
;
; Outputs:
;   C = 0  success
;   A/X    = bytes written
;   C = 1  failure
;   Y      = errno on failure
;
; Clobbers:
;   A, X, Y, tmp0, tmp1
;
; Notes:
;   - Uses shared request/result block in RAM
;   - Uses shared mailbox MMIO registers
;   - Scheduling is temporarily disabled during the transaction
; ------------------------------------------------------------

.proc rp_console_write
    ; Save requested transfer length
    sta rp_tmp
    stx rp_tmp+1

    ; Prevent preemption while mailbox state is live
    jsr sched_lock_enter

    ; Gain exclusive ownership of shared mailbox
    jsr rp_acquire_lock
	
	; wait for last command to finish
    jsr rp_wait_idle

    ; --------------------------------------------------------
    ; Fill request block in shared RAM
    ; --------------------------------------------------------
    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    lda rp_tmp
    sta RP_ARG1L
    lda rp_tmp+1
    sta RP_ARG1H

    stz RP_ARG2L
    stz RP_ARG2H
    stz RP_RES0L
    stz RP_RES0H
    stz RP_ERR
    stz RP_FLAGS
    stz RP_STATE

    ; --------------------------------------------------------
    ; Signal request start
    ; --------------------------------------------------------
    lda #RP_BUSY
    sta RP_STATUS

    lda #RP_CMD_CON_WRITE
    sta RP_DOORBELL

    ; --------------------------------------------------------
    ; Wait for completion
    ; --------------------------------------------------------
    jsr rp_wait_done
    bcs @fail

    ; Preserve result across cleanup
    lda RP_RES0L
    ldx RP_RES0H
    pha
    txa
    pha

    ; Return interface to idle and release ownership
    stz RP_STATUS

    jsr rp_release_lock
    jsr sched_lock_leave

    ; Restore AX result
    pla
    tax
    pla
    clc
    rts

@fail:
    stz RP_STATUS

    jsr rp_release_lock
    jsr sched_lock_leave
    sec
    rts
.endproc

; ------------------------------------------------------------
; rp_console_read_start
;
; Purpose:
;   Submit a console read request to the RP2350 and return
;   immediately.
;
; Input:
;   io_ptr -> destination buffer
;   A      = length low byte
;   X      = length high byte
;
; Return:
;   C clear = request submitted
;
; Synchronization:
;   - Acquires rp_lock.
;   - Does NOT acquire sched_lock.
;   - rp_lock remains held while request is in flight.
;   - rp_console_read_finish must release rp_lock.
;
; Important:
;   This routine is async with respect to RP completion, but it
;   still owns the global mailbox until finish runs.
; ------------------------------------------------------------

.proc rp_console_read_start
    ; Save requested transfer length
    sta rp_tmp
    stx rp_tmp+1

    ; Own the mailbox.
    ; No sched_lock here: other tasks must continue to run while
    ; the RP completes the request.
    jsr rp_acquire_lock

    ; Ensure no previous command is still visible in the mailbox.
    jsr rp_wait_idle

    ; --------------------------------------------------------
    ; Fill request block in shared RAM.
    ; --------------------------------------------------------

    ; Destination buffer pointer
    lda io_ptr
    sta RP_ARG0L
    lda io_ptr+1
    sta RP_ARG0H

    ; Requested length
    lda rp_tmp
    sta RP_ARG1L
    lda rp_tmp+1
    sta RP_ARG1H

    ; Clear unused args/result/status detail fields
    stz RP_ARG2L
    stz RP_ARG2H
    stz RP_RES0L
    stz RP_RES0H
    stz RP_ERR
    stz RP_FLAGS
    stz RP_STATE

    ; --------------------------------------------------------
    ; Signal request start.
    ;
    ; RP_STATUS must become BUSY before the doorbell write.
    ; The doorbell write is the interrupt-generating operation.
    ; --------------------------------------------------------
    lda #RP_BUSY
    sta RP_STATUS

    lda #RP_CMD_CON_READ
    sta RP_DOORBELL

    clc
    rts
.endproc

; ------------------------------------------------------------
; rp_console_read_finish
;
; Purpose:
;   Non-blocking completion check for an async console read.
;
; Return:
;   C clear = completed successfully
;             A/X = bytes read
;
;   C set   = not complete or failed
;             Y = E_OK  if still busy
;             Y = EIO   if RP reported error
;
; Synchronization:
;   - Assumes rp_console_read_start acquired rp_lock.
;   - Releases rp_lock only when RP_DONE or RP_ERROR is seen.
;   - Does NOT touch sched_lock.
; ------------------------------------------------------------

.proc rp_console_read_finish
    lda RP_STATUS
    cmp #RP_DONE
    beq @done

    cmp #RP_ERROR
    beq @error

    ; Still in progress.
    ; Keep rp_lock held. Caller must try again later.
    ldy #E_OK
    sec
    rts

@done:
    ; Fetch result before clearing RP_STATUS.
    lda RP_RES0L
    ldx RP_RES0H

    ; Mark mailbox interface idle again.
    stz RP_STATUS

    ; Release mailbox ownership.
    jsr rp_release_lock

    clc
    rts

@error:
    ; Preserve RP error in Y if you later map RP_ERR to errno.
    ; For now return generic EIO.
    stz RP_STATUS
    jsr rp_release_lock

    ldy #EIO
    sec
    rts
.endproc

; ------------------------------------------------------------
; rp_console_read
;
; Purpose:
;   Backward-compatible synchronous console read.
;
; Notes:
;   - Existing k_read can continue to tail-call this.
;   - This wrapper still busy-waits.
;   - It does not use sched_lock in the async part, but the
;     wrapper itself locks scheduling to preserve old semantics.
; ------------------------------------------------------------

.proc rp_console_read
    ; Preserve old synchronous behavior for current syscall path.
    jsr sched_lock_enter

    jsr rp_console_read_start
    bcs @fail_locked

@wait:
    jsr rp_console_read_finish
    bcc @done_locked

    ; Y = E_OK means still busy, not failure.
    cpy #E_OK
    beq @wait

@fail_locked:
    jsr sched_lock_leave
    sec
    rts

@done_locked:
    jsr sched_lock_leave
    clc
    rts
.endproc
