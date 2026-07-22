#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/fs.h>
#include <neox/io.h>
#include <neox/status.h>

#define PWD_BUFFER_SIZE ((neox_size_t)64u)

static char pwd_buffer[PWD_BUFFER_SIZE];
static const char pwd_cr[] = "\r";

static const char pwd_extra_message[] =
    "pwd: too many arguments\r";
static const char pwd_getcwd_message[] =
    "pwd: cannot get current directory\r";
static const char pwd_write_message[] =
    "pwd: write error\r";

/// <summary>
/// Executes the resident pwd applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_pwd(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t extra_argument;
    neox_size_t path_length;
    neox_status_t status;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &extra_argument) != 0u) {
        neox_applet_report(pwd_extra_message);
        return NEOX_STATUS_EINVAL;
    }

    path_length = 0u;
    status = neox_getcwd(
        pwd_buffer,
        PWD_BUFFER_SIZE,
        &path_length);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(pwd_getcwd_message);
        return status;
    }

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        pwd_buffer,
        path_length);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(pwd_write_message);
        return status;
    }

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        pwd_cr,
        (neox_size_t)1u);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(pwd_write_message);
    }

    return status;
}
