; ============================================================
; applet_scratch.asm
; NEOX nbox applet shared work area
;
; This module owns reusable applet scratch storage. Only one
; applet executes at a time inside one user context, so these
; buffers and temporary variables may be shared by applets.
; Spawned children run in separate contexts and therefore have
; separate private copies of this storage.
; ============================================================

.setcpu "65C02"

.include "syscall.inc"
.include "nbox.inc"

.export nbox_cwd_buf
.export nbox_dir_entry
.export nbox_cat_buf
.export nbox_dir_fd
.export nbox_file_fd
.export nbox_cp_src_fd
.export nbox_cp_dst_fd
.export nbox_src_idx
.export nbox_dst_idx
.export nbox_strlen_dirent_name

.segment "USER_DATA"

nbox_cwd_buf:
    .res NBOX_PATH_MAX

nbox_dir_entry:
    .res DIR_ENTRY_SIZE

nbox_cat_buf:
    .res NBOX_CAT_BUF_SIZE

nbox_dir_fd:
    .byte NBOX_DIR_FD_NONE

nbox_file_fd:
    .byte NBOX_FILE_FD_NONE

nbox_cp_src_fd:
    .byte NBOX_FILE_FD_NONE

nbox_cp_dst_fd:
    .byte NBOX_FILE_FD_NONE

nbox_src_idx:
    .byte 0

nbox_dst_idx:
    .byte 0

.segment "USER_TEXT"

; ------------------------------------------------------------
; nbox_strlen_dirent_name
;
; Return:
;   Y = length of nbox_dir_entry.name, capped at DIR_ENTRY_NAME_SIZE
; ------------------------------------------------------------
.proc nbox_strlen_dirent_name
    ldy #0
@loop:
    cpy #DIR_ENTRY_NAME_SIZE
    bcs @done
    lda nbox_dir_entry + dir_entry::name,y
    beq @done
    iny
    bra @loop
@done:
    rts
.endproc
