#ifndef NEOX_APPLET_H
#define NEOX_APPLET_H

#include <stddef.h>
#include <stdint.h>

#include <neox/types.h>

typedef struct neox_applet_context {
    const char* line;
    neox_size_t line_length;
} neox_applet_context_t;

typedef struct neox_arg {
    const char* data;
    neox_size_t length;
} neox_arg_t;

typedef struct neox_arg_cursor {
    const char* line;
    neox_size_t line_length;
    neox_size_t offset;
} neox_arg_cursor_t;

typedef char neox_applet_context_size_must_be_4[
    (sizeof(neox_applet_context_t) == 4u) ? 1 : -1];
typedef char neox_applet_context_line_offset_must_be_0[
    (offsetof(neox_applet_context_t, line) == 0u) ? 1 : -1];
typedef char neox_applet_context_length_offset_must_be_2[
    (offsetof(neox_applet_context_t, line_length) == 2u) ? 1 : -1];

/// <summary>
/// Initializes an argument iterator for an applet launch line.
/// </summary>
/// <param name="cursor">Iterator state to initialize.</param>
/// <param name="context">Raw launch-line context.</param>
void neox_arg_cursor_init(
    neox_arg_cursor_t* cursor,
    const neox_applet_context_t* context);

/// <summary>
/// Returns the next whitespace-separated argument span.
/// </summary>
/// <param name="cursor">Iterator state.</param>
/// <param name="argument_out">Receives the next argument span.</param>
/// <returns>1 when an argument was returned; otherwise 0.</returns>
uint8_t neox_arg_next(
    neox_arg_cursor_t* cursor,
    neox_arg_t* argument_out);

#endif /* NEOX_APPLET_H */
