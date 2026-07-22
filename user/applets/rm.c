#include <neox/applet.h>
#include <neox/fs.h>
#include <neox/status.h>

#include <neox_applet_path.h>

static const char missing_message[] = "rm: missing file\r";
static const char extra_message[] = "rm: too many arguments\r";
static const char not_found_message[] = "rm: file does not exist\r";
static const char invalid_name_message[] = "rm: invalid file name\r";
static const char failure_message[] = "rm: cannot remove file\r";

/// <summary>
/// Executes the resident rm applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_rm(const neox_applet_context_t* context)
{
    return neox_applet_run_one_path(
        context,
        missing_message,
        extra_message,
        not_found_message,
        invalid_name_message,
        failure_message,
        neox_delete);
}
