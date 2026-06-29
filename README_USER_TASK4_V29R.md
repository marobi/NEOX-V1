# V29R - User Task 4 FS smoke test

Adds a fourth boot user task to exercise the read-only RP filesystem syscall path from user mode.

Changes:
- `include/config.inc`: `MAX_PROCS` raised from 4 to 5 so PID 4 can exist.
- `user/user_entry.asm`: boot task count raised to 4 and context 4 entry added.
- `user/user_space.asm`: includes `task4.asm`.
- `user/task4.asm`: opens `TEST.TXT` on device 0, reads up to 64 bytes, writes the bytes to STDOUT, closes the FD, and exits.

Expected output includes:

```text
T4 FS START
This is a test
```

Because `MAX_PROCS` changes the shared-state layout, the RP debug/shared-state mirror must also be updated to use `MAX_PROCS = 5` before status dumps are trusted.
