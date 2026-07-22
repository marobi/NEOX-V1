#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/io.h>
#include <neox/process.h>
#include <neox/status.h>

static const char ps_header[] =
    "PID PPID ST  WAIT OBJ SIG\r";
static const char ps_extra_message[] =
    "ps: too many arguments\r";
static const char ps_read_message[] =
    "ps: cannot read process table\r";
static const char ps_write_message[] =
    "ps: write error\r";
static const char ps_space[] = " ";
static const char ps_cr[] = "\r";

static const char ps_state_empty[] = "EMP";
static const char ps_state_new[] = "NEW";
static const char ps_state_ready[] = "RDY";
static const char ps_state_running[] = "RUN";
static const char ps_state_blocked[] = "BLK";
static const char ps_state_stopped[] = "STP";
static const char ps_state_zombie[] = "ZOM";
static const char ps_state_unknown[] = "???";

static const char ps_wait_none[] = "----";
static const char ps_wait_console[] = "CON ";
static const char ps_wait_device[] = "DEV ";
static const char ps_wait_pipe_read[] = "PIPR";
static const char ps_wait_timer[] = "TIMR";
static const char ps_wait_process[] = "PROC";
static const char ps_wait_lock[] = "LOCK";
static const char ps_wait_pipe_write[] = "PIPW";
static const char ps_wait_rp[] = "RP  ";
static const char ps_wait_unknown[] = "????";

static const char ps_object_none[] = "---";
static const char ps_object_file_io[] = "FIO";
static const char ps_object_process[] = "PRC";
static const char ps_object_unknown[] = "???";

static char ps_hex_buffer[2];
static char ps_decimal_buffer[NEOX_APPLET_U32_DECIMAL_SIZE];
static neox_process_info_t ps_info;

static neox_status_t ps_write_text(const char* text)
{
    return neox_applet_write_string(
        NEOX_STDOUT_FD,
        text);
}

static neox_status_t ps_write_hex(uint8_t value)
{
    neox_applet_format_hex8(value, ps_hex_buffer);

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        ps_hex_buffer,
        (neox_size_t)2u);
}

/// <summary>
/// Writes one signal number as right-aligned decimal in a two-character field.
/// </summary>
/// <param name="value">Linux-compatible signal number.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the write status.</returns>
static neox_status_t ps_write_signal_decimal(uint8_t value)
{
    neox_size_t length;
    neox_status_t status;

    length = neox_applet_format_u32(
        (uint32_t)value,
        ps_decimal_buffer);

    if (length < (neox_size_t)2u) {
        status = neox_applet_write_all(
            NEOX_STDOUT_FD,
            ps_space,
            (neox_size_t)1u);
        if (status != NEOX_STATUS_OK) {
            return status;
        }
    }

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        ps_decimal_buffer,
        length);
}

static const char* ps_state_text(uint8_t state)
{
    switch (state) {
        case NEOX_PROCESS_EMPTY:
            return ps_state_empty;
        case NEOX_PROCESS_NEW:
            return ps_state_new;
        case NEOX_PROCESS_READY:
            return ps_state_ready;
        case NEOX_PROCESS_RUNNING:
            return ps_state_running;
        case NEOX_PROCESS_BLOCKED:
            return ps_state_blocked;
        case NEOX_PROCESS_STOPPED:
            return ps_state_stopped;
        case NEOX_PROCESS_ZOMBIE:
            return ps_state_zombie;
        default:
            return ps_state_unknown;
    }
}

static const char* ps_wait_text(uint8_t wait_reason)
{
    switch (wait_reason) {
        case NEOX_WAIT_NONE:
            return ps_wait_none;
        case NEOX_WAIT_CONSOLE:
            return ps_wait_console;
        case NEOX_WAIT_DEVICE:
            return ps_wait_device;
        case NEOX_WAIT_PIPE_READ:
            return ps_wait_pipe_read;
        case NEOX_WAIT_TIMER:
            return ps_wait_timer;
        case NEOX_WAIT_PROCESS:
            return ps_wait_process;
        case NEOX_WAIT_LOCK:
            return ps_wait_lock;
        case NEOX_WAIT_PIPE_WRITE:
            return ps_wait_pipe_write;
        case NEOX_WAIT_RP:
            return ps_wait_rp;
        default:
            return ps_wait_unknown;
    }
}

static const char* ps_object_text(
    uint8_t wait_reason,
    uint8_t wait_object)
{
    if (wait_reason == NEOX_WAIT_NONE) {
        return ps_object_none;
    }

    if (wait_reason != NEOX_WAIT_LOCK) {
        return 0;
    }

    if (wait_object == NEOX_LOCK_FILE_IO) {
        return ps_object_file_io;
    }

    if (wait_object == NEOX_LOCK_PROCESS) {
        return ps_object_process;
    }

    return ps_object_unknown;
}

static neox_status_t ps_print_row(const neox_process_info_t* info)
{
    const char* object_text;
    neox_status_t status;

    status = ps_write_hex(info->pid);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_text("  ");
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_hex(info->parent_pid);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_text("   ");
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_text(ps_state_text(info->state));
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        ps_space,
        (neox_size_t)1u);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_text(ps_wait_text(info->wait_reason));
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        ps_space,
        (neox_size_t)1u);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    object_text = ps_object_text(
        info->wait_reason,
        info->wait_object);

    if (object_text != 0) {
        status = ps_write_text(object_text);
    } else {
        status = ps_write_hex(info->wait_object);
        if (status == NEOX_STATUS_OK) {
            status = neox_applet_write_all(
                NEOX_STDOUT_FD,
                ps_space,
                (neox_size_t)1u);
        }
    }

    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_text(" ");
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = ps_write_signal_decimal(info->signal_pending);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        ps_cr,
        (neox_size_t)1u);
}

/// <summary>
/// Executes the resident ps applet.
/// </summary>
/// <param name="context">Complete raw launch argument line.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure status.</returns>
neox_status_t neox_applet_ps(const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t extra_argument;
    neox_pid_t pid;
    neox_status_t status;

    neox_arg_cursor_init(&cursor, context);

    if (neox_arg_next(&cursor, &extra_argument) != 0u) {
        neox_applet_report(ps_extra_message);
        return NEOX_STATUS_EINVAL;
    }

    status = ps_write_text(ps_header);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(ps_write_message);
        return status;
    }

    for (pid = 0u; pid < NEOX_MAX_PROCESSES; ++pid) {
        status = neox_get_process_info(pid, &ps_info);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(ps_read_message);
            return status;
        }

        if (ps_info.state == NEOX_PROCESS_EMPTY) {
            continue;
        }

        status = ps_print_row(&ps_info);
        if (status != NEOX_STATUS_OK) {
            neox_applet_report(ps_write_message);
            return status;
        }
    }

    return NEOX_STATUS_OK;
}
