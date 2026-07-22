#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/io.h>
#include <neox/status.h>

static const char echo_space[] = " ";
static const char echo_cr[] = "\r";

/// <summary>
/// Executes the resident echo applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success; otherwise the first write error.</returns>
neox_status_t neox_applet_echo(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t argument;
    neox_status_t status;
    uint8_t emitted_argument;

    neox_arg_cursor_init(&cursor, context);
    emitted_argument = 0u;

    while (neox_arg_next(&cursor, &argument) != 0u) {
        if (emitted_argument != 0u) {
            status = neox_applet_write_all(
                NEOX_STDOUT_FD,
                echo_space,
                (neox_size_t)1u);
            if (status != NEOX_STATUS_OK) {
                return status;
            }
        }

        status = neox_applet_write_all(
            NEOX_STDOUT_FD,
            argument.data,
            argument.length);
        if (status != NEOX_STATUS_OK) {
            return status;
        }

        emitted_argument = 1u;
    }

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        echo_cr,
        (neox_size_t)1u);
}
