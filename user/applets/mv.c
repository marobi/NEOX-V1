#include <neox/applet.h>
#include <neox/fs.h>
#include <neox/status.h>

#include <neox_applet_two_path.h>

static const char missing_message[] =
    "mv: source and destination required\r";
static const char extra_message[] =
    "mv: too many arguments\r";
static const char not_found_message[] =
    "mv: source does not exist\r";
static const char invalid_name_message[] =
    "mv: invalid source or destination name\r";
static const char failure_message[] =
    "mv: cannot rename path\r";

/// <summary>
/// Executes the resident mv applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_mv(const neox_applet_context_t* context)
{
    return neox_applet_run_two_paths(
        context,
        missing_message,
        extra_message,
        not_found_message,
        invalid_name_message,
        failure_message,
        neox_rename);
}
