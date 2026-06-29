# NEOX V29P - FS mailbox import fix

Fixes the V29O build failure where `kernel/fd.asm` called `rp_fs_read` and `rp_fs_close` without declaring them as imports.

Changed:
- `kernel/fd.asm` now imports `rp_fs_read` and `rp_fs_close` from `kernel/rp_fs_io.asm`.

No ABI or behavior changes.
