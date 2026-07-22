#include <neox/applet.h>
#include <neox/fs.h>
#include <neox/status.h>

#include <neox_applet_path.h>

static const char missing_message[] = "mkdir: missing directory\r";
static const char extra_message[] = "mkdir: too many arguments\r";
static const char invalid_name_message[] = "mkdir: invalid directory name\r";
static const char failure_message[] = "mkdir: cannot create directory\r";

/// <summary>
/// Executes the resident mkdir applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_mkdir(const neox_applet_context_t* context)
{
    return neox_applet_run_one_path(
        context,
        missing_message,
        extra_message,
        0,
        invalid_name_message,
        failure_message,
        neox_mkdir);
}
