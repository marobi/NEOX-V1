#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/fs.h>
#include <neox/io.h>
#include <neox/status.h>

#define LS_PATH_SIZE ((neox_size_t)64u)
#define LS_NAME_FIELD_WIDTH ((neox_size_t)13u)

static char ls_path[LS_PATH_SIZE];
static neox_dir_entry_t ls_entry;
static char ls_decimal[NEOX_APPLET_U32_DECIMAL_SIZE];
static const char ls_default_path[] = ".";
static const char ls_directory_text[] = "<DIR>";
static const char ls_cr[] = "\r";
static const char ls_space[] = " ";

static const char ls_extra_message[] =
    "ls: too many arguments\r";
static const char ls_not_found_message[] =
    "ls: directory does not exist\r";
static const char ls_invalid_name_message[] =
    "ls: invalid directory name\r";
static const char ls_open_message[] =
    "ls: cannot open directory\r";
static const char ls_read_message[] =
    "ls: read error\r";
static const char ls_close_message[] =
    "ls: close error\r";
static const char ls_write_message[] =
    "ls: write error\r";

static neox_status_t ls_write_padding(neox_size_t count)
{
    neox_status_t status;

    while (count != 0u) {
        status = neox_applet_write_all(
            NEOX_STDOUT_FD,
            ls_space,
            (neox_size_t)1u);
        if (status != NEOX_STATUS_OK) {
            return status;
        }

        --count;
    }

    return NEOX_STATUS_OK;
}

static neox_status_t ls_print_entry(const neox_dir_entry_t* entry)
{
    neox_size_t name_length;
    neox_size_t value_length;
    neox_status_t status;

    name_length = neox_applet_string_length(entry->name);

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        entry->name,
        name_length);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    if (name_length < LS_NAME_FIELD_WIDTH) {
        status = ls_write_padding(LS_NAME_FIELD_WIDTH - name_length);
    } else {
        status = ls_write_padding((neox_size_t)1u);
    }

    if (status != NEOX_STATUS_OK) {
        return status;
    }

    if ((entry->attributes & NEOX_FILE_ATTRIBUTE_DIRECTORY) != 0u) {
        status = neox_applet_write_string(
            NEOX_STDOUT_FD,
            ls_directory_text);
    } else {
        value_length = neox_applet_format_u32(
            entry->size,
            ls_decimal);
        status = neox_applet_write_all(
            NEOX_STDOUT_FD,
            ls_decimal,
            value_length);
    }

    if (status != NEOX_STATUS_OK) {
        return status;
    }

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        ls_cr,
        (neox_size_t)1u);
}

static neox_status_t ls_list_pass(
    const char* path,
    uint8_t directories)
{
    neox_fd_t directory_fd;
    neox_status_t status;
    neox_status_t close_status;
    uint8_t end;
    uint8_t is_directory;

    status = neox_opendir(path, &directory_fd);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    for (;;) {
        end = 0u;
        status = neox_readdir(
            directory_fd,
            &ls_entry,
            &end);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(ls_read_message);
            (void)neox_closedir(directory_fd);
            return status;
        }

        if (end != 0u) {
            break;
        }

        is_directory =
            (uint8_t)((ls_entry.attributes &
                       NEOX_FILE_ATTRIBUTE_DIRECTORY) != 0u);

        if (is_directory == directories) {
            status = ls_print_entry(&ls_entry);
            if (status != NEOX_STATUS_OK) {
                neox_applet_report(ls_write_message);
                (void)neox_closedir(directory_fd);
                return status;
            }
        }
    }

    close_status = neox_closedir(directory_fd);
    if (close_status != NEOX_STATUS_OK) {
        neox_applet_report(ls_close_message);
        return close_status;
    }

    return NEOX_STATUS_OK;
}

/// <summary>
/// Executes the resident ls applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_ls(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t path_argument;
    neox_arg_t extra_argument;
    neox_status_t status;
    const char* path;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &path_argument) == 0u) {
        path = ls_default_path;
    } else {
        if (neox_arg_next(&cursor, &extra_argument) != 0u) {
            neox_applet_report(ls_extra_message);
            return NEOX_STATUS_EINVAL;
        }

        status = neox_applet_copy_argument(
            &path_argument,
            ls_path,
            LS_PATH_SIZE);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(ls_invalid_name_message);
            return status;
        }

        path = ls_path;
    }

    status = ls_list_pass(path, 1u);
    if (status != NEOX_STATUS_OK) {
        if (status == NEOX_STATUS_ENOENT) {
            neox_applet_report(ls_not_found_message);
        } else if (status == NEOX_STATUS_EINVAL) {
            neox_applet_report(ls_invalid_name_message);
        } else if ((status != NEOX_STATUS_EIO) &&
                   (status != NEOX_STATUS_EBADF)) {
            neox_applet_report(ls_open_message);
        }

        return status;
    }

    status = ls_list_pass(path, 0u);
    if (status != NEOX_STATUS_OK) {
        if (status == NEOX_STATUS_ENOENT) {
            neox_applet_report(ls_not_found_message);
        } else if (status == NEOX_STATUS_EINVAL) {
            neox_applet_report(ls_invalid_name_message);
        } else if ((status != NEOX_STATUS_EIO) &&
                   (status != NEOX_STATUS_EBADF)) {
            neox_applet_report(ls_open_message);
        }
    }

    return status;
}
