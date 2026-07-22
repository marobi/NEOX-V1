#ifndef NEOX_COMPILER_H
#define NEOX_COMPILER_H

/*
 * Compiler-neutral public declarations belong in libneox/include/neox.
 * Compiler-specific calling conventions must remain inside libneox/cc65.
 */

#if defined(__CC65__)
#define NEOX_COMPILER_CC65 1
#else
#define NEOX_COMPILER_CC65 0
#endif

#endif /* NEOX_COMPILER_H */
