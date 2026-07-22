#include <neox/applet.h>

/// <summary>
/// Tests whether a launch-line byte separates arguments.
/// </summary>
/// <param name="value">Byte to classify.</param>
/// <returns>1 for space or horizontal tab; otherwise 0.</returns>
static uint8_t neox_arg_is_separator(char value)
{
    return (uint8_t)((value == ' ') || (value == '\t'));
}

/// <summary>
/// Initializes an argument iterator for an applet launch line.
/// </summary>
/// <param name="cursor">Iterator state to initialize.</param>
/// <param name="context">Raw launch-line context.</param>
void neox_arg_cursor_init(
    neox_arg_cursor_t* cursor,
    const neox_applet_context_t* context)
{
    cursor->line = context->line;
    cursor->line_length = context->line_length;
    cursor->offset = 0u;
}

/// <summary>
/// Returns the next whitespace-separated argument span.
/// </summary>
/// <param name="cursor">Iterator state.</param>
/// <param name="argument_out">Receives the next argument span.</param>
/// <returns>1 when an argument was returned; otherwise 0.</returns>
uint8_t neox_arg_next(
    neox_arg_cursor_t* cursor,
    neox_arg_t* argument_out)
{
    neox_size_t start;

    while ((cursor->offset < cursor->line_length) &&
           neox_arg_is_separator(cursor->line[cursor->offset])) {
        ++cursor->offset;
    }

    if (cursor->offset >= cursor->line_length) {
        argument_out->data = (const char*)0;
        argument_out->length = 0u;
        return 0u;
    }

    start = cursor->offset;

    while ((cursor->offset < cursor->line_length) &&
           !neox_arg_is_separator(cursor->line[cursor->offset])) {
        ++cursor->offset;
    }

    argument_out->data = cursor->line + start;
    argument_out->length = cursor->offset - start;
    return 1u;
}
