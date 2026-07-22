#ifndef NEOX_APPLET_TWO_PATH_H
#define NEOX_APPLET_TWO_PATH_H

#include <neox/applet.h>
#include <neox/status.h>
#include <neox/types.h>

typedef neox_status_t (*neox_two_path_operation_t)(
    const char* first_path,
    const char* second_path);

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
    neox_two_path_operation_t operation);

#endif /* NEOX_APPLET_TWO_PATH_H */
