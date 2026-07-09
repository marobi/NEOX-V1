; ============================================================
; common.inc
; NEOX nbox applet shared imports
; ============================================================

.include "syscall.inc"
.include "process.inc"
.include "nbox.inc"

.import nbox_line_buf
.import nbox_arg_buf
.import nbox_arg2_buf
.import nbox_arg_len
.import nbox_arg2_len
.import nbox_cwd_buf
.import nbox_dir_entry
.import nbox_cat_buf
.import nbox_dir_fd
.import nbox_file_fd
.import nbox_cp_src_fd
.import nbox_cp_dst_fd
.import nbox_src_idx
.import nbox_dst_idx
.import nbox_print_msg
.import nbox_print_cr
.import nbox_print_help
.import nbox_print_unknown
.import nbox_print_arg_fail
.import nbox_print_space
.import nbox_print_hex_byte
.import nbox_copy_arg_from_y
.import nbox_copy_two_args_from_y
.import nbox_require_arg
.import nbox_require_two_args
.import nbox_default_arg_dot_if_empty
.import nbox_default_arg_root_if_empty
.import nbox_strlen_dirent_name
