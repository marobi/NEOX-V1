#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/status.h>

#include <neox_applet_two_path.h>

#define APPLET_PATH_MAX ((neox_size_t)64u)

static char first_path_buffer[APPLET_PATH_MAX];
static char second_path_buffer[APPLET_PATH_MAX];

/// <summary>
/// Executes an applet that requires exactly two pathnames.
/// </summary>
/// <param name="context">Raw applet launch-line context.</param>
/// <param name="missing_message">Missing-argument diagnostic.</param>
/// <param name="extra_message">Too-many-arguments diagnostic.</param>
/// <param name="not_found_message">Optional ENOENT diagnostic.</param>
/// <param name="invalid_name_message">Optional EINVAL diagnostic.</param>
/// <param name="failure_message">Generic operation-failure diagnostic.</param>
/// <param name="operation">Two-path filesystem operation.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_run_two_paths(
    const neox_applet_context_t* context,
    const char* missing_message,
    const char* extra_message,
    const char* not_found_message,
    const char* invalid_name_message,
    const char* failure_message,
    neox_two_path_operation_t operation)
{
    neox_arg_cursor_t cursor;
    neox_arg_t first_argument;
    neox_arg_t second_argument;
    neox_arg_t extra_argument;
    neox_status_t status;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &first_argument) == 0u) {
        neox_applet_report(missing_message);
        return NEOX_STATUS_EINVAL;
    }

    if (neox_arg_next(&cursor, &second_argument) == 0u) {
        neox_applet_report(missing_message);
        return NEOX_STATUS_EINVAL;
    }

    if (neox_arg_next(&cursor, &extra_argument) != 0u) {
        neox_applet_report(extra_message);
        return NEOX_STATUS_EINVAL;
    }

    status = neox_applet_copy_argument(
        &first_argument,
        first_path_buffer,
        APPLET_PATH_MAX);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(invalid_name_message);
        return status;
    }

    status = neox_applet_copy_argument(
        &second_argument,
        second_path_buffer,
        APPLET_PATH_MAX);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(invalid_name_message);
        return status;
    }

    status = operation(first_path_buffer, second_path_buffer);
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
