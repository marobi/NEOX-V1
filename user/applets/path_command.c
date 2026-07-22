#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/status.h>

#include <neox_applet_path.h>

#define APPLET_PATH_MAX ((neox_size_t)64u)

static char applet_path_buffer[APPLET_PATH_MAX];

/// <summary>
/// Executes an applet that requires exactly one pathname.
/// </summary>
/// <param name="context">Raw applet launch-line context.</param>
/// <param name="missing_message">Missing-argument diagnostic.</param>
/// <param name="extra_message">Too-many-arguments diagnostic.</param>
/// <param name="not_found_message">Optional ENOENT diagnostic.</param>
/// <param name="invalid_name_message">Optional EINVAL diagnostic.</param>
/// <param name="failure_message">Filesystem-operation failure diagnostic.</param>
/// <param name="operation">Filesystem operation to invoke.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_run_one_path(
    const neox_applet_context_t* context,
    const char* missing_message,
    const char* extra_message,
    const char* not_found_message,
    const char* invalid_name_message,
    const char* failure_message,
    neox_path_operation_t operation)
{
    neox_arg_cursor_t cursor;
    neox_arg_t path_argument;
    neox_arg_t extra_argument;
    neox_status_t status;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &path_argument) == 0u) {
        neox_applet_report(missing_message);
        return NEOX_STATUS_EINVAL;
    }

    if (neox_arg_next(&cursor, &extra_argument) != 0u) {
        neox_applet_report(extra_message);
        return NEOX_STATUS_EINVAL;
    }

    status = neox_applet_copy_argument(
        &path_argument,
        applet_path_buffer,
        APPLET_PATH_MAX);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report("path: pathname too long\r");
        return status;
    }

    status = operation(applet_path_buffer);
    if (status != NEOX_STATUS_OK) {
        const char* message;

        message = failure_message;

        if ((status == NEOX_STATUS_ENOENT) &&
            (not_found_message != 0)) {
            message = not_found_message;
        } else if ((status == NEOX_STATUS_EINVAL) &&
                   (invalid_name_message != 0)) {
            message = invalid_name_message;
        }

        neox_applet_report(message);
    }

    return status;
}
