#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/io.h>
#include <neox/status.h>

#define CP_BUFFER_SIZE ((neox_size_t)64u)

static char cp_source_path[NEOX_PATH_MAX];
static char cp_destination_path[NEOX_PATH_MAX];
static uint8_t cp_buffer[CP_BUFFER_SIZE];

static const char cp_missing_message[] =
    "cp: source and destination required\r";
static const char cp_extra_message[] =
    "cp: too many arguments\r";
static const char cp_source_missing_message[] =
    "cp: source does not exist\r";
static const char cp_invalid_name_message[] =
    "cp: invalid source or destination name\r";
static const char cp_same_path_message[] =
    "cp: source and destination are the same\r";
static const char cp_open_source_message[] =
    "cp: cannot open source\r";
static const char cp_open_destination_message[] =
    "cp: cannot create destination\r";
static const char cp_read_message[] =
    "cp: read error\r";
static const char cp_write_message[] =
    "cp: write error\r";
static const char cp_close_message[] =
    "cp: close error\r";

static uint8_t cp_paths_equal(
    const char* first,
    const char* second)
{
    neox_size_t index;

    index = 0u;
    for (;;) {
        if (first[index] != second[index]) {
            return 0u;
        }

        if (first[index] == '\0') {
            return 1u;
        }

        ++index;
    }
}

static void cp_close_after_failure(
    neox_fd_t source_fd,
    uint8_t source_open,
    neox_fd_t destination_fd,
    uint8_t destination_open)
{
    if (source_open != 0u) {
        (void)neox_close(source_fd);
    }

    if (destination_open != 0u) {
        (void)neox_close(destination_fd);
    }
}

/// <summary>
/// Executes the resident cp applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_cp(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t source_argument;
    neox_arg_t destination_argument;
    neox_arg_t extra_argument;
    neox_fd_t source_fd;
    neox_fd_t destination_fd;
    neox_status_t status;
    neox_status_t close_status;
    uint8_t source_open;
    uint8_t destination_open;

    source_open = 0u;
    destination_open = 0u;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &source_argument) == 0u) {
        neox_applet_report(cp_missing_message);
        return NEOX_STATUS_EINVAL;
    }

    if (neox_arg_next(&cursor, &destination_argument) == 0u) {
        neox_applet_report(cp_missing_message);
        return NEOX_STATUS_EINVAL;
    }

    if (neox_arg_next(&cursor, &extra_argument) != 0u) {
        neox_applet_report(cp_extra_message);
        return NEOX_STATUS_EINVAL;
    }

    status = neox_applet_copy_argument(
        &source_argument,
        cp_source_path,
        NEOX_PATH_MAX);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(cp_invalid_name_message);
        return status;
    }

    status = neox_applet_copy_argument(
        &destination_argument,
        cp_destination_path,
        NEOX_PATH_MAX);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(cp_invalid_name_message);
        return status;
    }

    if (cp_paths_equal(cp_source_path, cp_destination_path) != 0u) {
        neox_applet_report(cp_same_path_message);
        return NEOX_STATUS_EINVAL;
    }

    status = neox_open(
        cp_source_path,
        NEOX_OPEN_READ,
        &source_fd);
    if (status != NEOX_STATUS_OK) {
        if (status == NEOX_STATUS_ENOENT) {
            neox_applet_report(cp_source_missing_message);
        } else if (status == NEOX_STATUS_EINVAL) {
            neox_applet_report(cp_invalid_name_message);
        } else {
            neox_applet_report(cp_open_source_message);
        }

        return status;
    }
    source_open = 1u;

    status = neox_open(
        cp_destination_path,
        NEOX_OPEN_WRITE_TRUNC,
        &destination_fd);
    if (status != NEOX_STATUS_OK) {
        if (status == NEOX_STATUS_EINVAL) {
            neox_applet_report(cp_invalid_name_message);
        } else {
            neox_applet_report(cp_open_destination_message);
        }

        cp_close_after_failure(
            source_fd,
            source_open,
            destination_fd,
            destination_open);
        return status;
    }
    destination_open = 1u;

    for (;;) {
        neox_size_t received;

        received = 0u;
        status = neox_read(
            source_fd,
            cp_buffer,
            CP_BUFFER_SIZE,
            &received);

        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cp_read_message);
            cp_close_after_failure(
                source_fd,
                source_open,
                destination_fd,
                destination_open);
            return status;
        }

        if (received == 0u) {
            break;
        }

        status = neox_applet_write_all(
            destination_fd,
            cp_buffer,
            received);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(cp_write_message);
            cp_close_after_failure(
                source_fd,
                source_open,
                destination_fd,
                destination_open);
            return status;
        }
    }

    close_status = neox_close(source_fd);
    source_open = 0u;
    if (close_status != NEOX_STATUS_OK) {
        neox_applet_report(cp_close_message);
        (void)neox_close(destination_fd);
        return close_status;
    }

    close_status = neox_close(destination_fd);
    destination_open = 0u;
    if (close_status != NEOX_STATUS_OK) {
        neox_applet_report(cp_close_message);
        return close_status;
    }

    return NEOX_STATUS_OK;
}
