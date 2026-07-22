#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/fs.h>
#include <neox/status.h>

#define CD_PATH_MAX ((neox_size_t)64u)

static char cd_path[CD_PATH_MAX];

static const char cd_extra_message[] =
    "cd: too many arguments\r";
static const char cd_not_found_message[] =
    "cd: directory does not exist\r";
static const char cd_invalid_name_message[] =
    "cd: invalid directory name\r";
static const char cd_failure_message[] =
    "cd: cannot change directory\r";

/// <summary>
/// Executes the resident cd applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the chdir status.</returns>
neox_status_t neox_applet_cd(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t directory_argument;
    neox_arg_t extra_argument;
    neox_status_t status;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &directory_argument) == 0u) {
        cd_path[0] = '/';
        cd_path[1] = '\0';
    } else {
        if (neox_arg_next(&cursor, &extra_argument) != 0u) {
            neox_applet_report(cd_extra_message);
            return NEOX_STATUS_EINVAL;
        }

        status = neox_applet_copy_argument(
            &directory_argument,
            cd_path,
            CD_PATH_MAX);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cd_invalid_name_message);
            return status;
        }
    }

    status = neox_chdir(cd_path);
    if (status != NEOX_STATUS_OK) {
        if (status == NEOX_STATUS_ENOENT) {
            neox_applet_report(cd_not_found_message);
        } else if (status == NEOX_STATUS_EINVAL) {
            neox_applet_report(cd_invalid_name_message);
        } else {
            neox_applet_report(cd_failure_message);
        }
    }

    return status;
}
