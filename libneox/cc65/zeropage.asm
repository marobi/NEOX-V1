; ============================================================
; zeropage.asm
; NEOX libneox - cc65 runtime zero-page storage
;
; Purpose:
;   Provides the zero-page symbols expected by cc65-generated code.
;   The complete block is process-private because zero page belongs
;   to the active MMU context.
;
; Allocation:
;   26 bytes in the C_ZEROPAGE segment, linked inside $20-$7F.
;
; Notes:
;   - These symbols must not overlap the NEOX kernel ZP workspace.
;   - Keep the order compatible with the cc65 V2.19 runtime layout.
; ============================================================

.setcpu "65C02"

.exportzp c_sp
.exportzp sreg
.exportzp regsave
.exportzp ptr1
.exportzp ptr2
.exportzp ptr3
.exportzp ptr4
.exportzp tmp1
.exportzp tmp2
.exportzp tmp3
.exportzp tmp4
.exportzp regbank

.segment "C_ZEROPAGE": zeropage

c_sp:       .res 2
sreg:       .res 2
regsave:    .res 4
ptr1:       .res 2
ptr2:       .res 2
ptr3:       .res 2
ptr4:       .res 2
tmp1:       .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
regbank:    .res 6
