#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/io.h>
#include <neox/status.h>

#define CAT_BUFFER_SIZE ((neox_size_t)64u)

static char cat_path[NEOX_PATH_MAX];
static uint8_t cat_buffer[CAT_BUFFER_SIZE];

static const char cat_too_many_message[] = "cat: too many arguments\r";
static const char cat_path_long_message[] = "cat: pathname too long\r";
static const char cat_open_message[] = "cat: cannot open file\r";
static const char cat_read_message[] = "cat: read error\r";
static const char cat_write_message[] = "cat: write error\r";
static const char cat_close_message[] = "cat: close error\r";

/// <summary>
/// Copies one descriptor to inherited standard output until EOF.
/// </summary>
/// <param name="source_fd">Descriptor to read.</param>
/// <returns>NEOX_STATUS_OK on EOF; otherwise the first I/O error.</returns>
static neox_status_t cat_copy_descriptor(neox_fd_t source_fd)
{
    for (;;) {
        neox_size_t received;
        neox_status_t status;

        received = 0u;
        status = neox_read(
            source_fd,
            cat_buffer,
            CAT_BUFFER_SIZE,
            &received);

        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cat_read_message);
            return status;
        }

        if (received == 0u) {
            return NEOX_STATUS_OK;
        }

        status = neox_applet_write_all(
            NEOX_STDOUT_FD,
            cat_buffer,
            received);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cat_write_message);
            return status;
        }
    }
}

/// <summary>
/// Executes the resident cat applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success; otherwise the first failure status.</returns>
neox_status_t neox_applet_cat(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t pathname;
    neox_arg_t extra;
    neox_fd_t source_fd;
    neox_status_t status;
    uint8_t close_source;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &pathname) == 0u) {
        source_fd = NEOX_STDIN_FD;
        close_source = 0u;
    } else {
        if (neox_arg_next(&cursor, &extra) != 0u) {
            neox_applet_report(cat_too_many_message);
            return NEOX_STATUS_EINVAL;
        }

        status = neox_applet_copy_argument(
            &pathname,
            cat_path,
            NEOX_PATH_MAX);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cat_path_long_message);
            return status;
        }

        status = neox_open(cat_path, NEOX_OPEN_READ, &source_fd);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cat_open_message);
            return status;
        }

        close_source = 1u;
    }

    status = cat_copy_descriptor(source_fd);

    if (close_source != 0u) {
        neox_status_t close_status;

        close_status = neox_close(source_fd);
        if ((status == NEOX_STATUS_OK) &&
            (close_status != NEOX_STATUS_OK)) {
            neox_applet_report(cat_close_message);
            status = close_status;
        }
    }

    return status;
}
