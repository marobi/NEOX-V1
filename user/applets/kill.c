#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/process.h>
#include <neox/signal.h>
#include <neox/status.h>

static const char kill_usage_message[] =
    "kill: usage: kill -SIGNAL PID\r";
static const char kill_invalid_signal_message[] =
    "kill: invalid signal\r";
static const char kill_invalid_pid_message[] =
    "kill: invalid pid\r";
static const char kill_failed_message[] =
    "kill: signal failed\r";

/// <summary>
/// Parses one nonempty unsigned decimal argument with an upper bound.
/// </summary>
/// <param name="argument">Argument span containing decimal digits.</param>
/// <param name="maximum">Largest accepted value.</param>
/// <param name="value_out">Receives the parsed byte.</param>
/// <returns>One on success, otherwise zero.</returns>
static uint8_t kill_parse_decimal(
    const neox_arg_t* argument,
    uint8_t maximum,
    uint8_t* value_out)
{
    neox_size_t index;
    uint16_t value;

    if (argument->length == 0u) {
        return 0u;
    }

    value = 0u;

    for (index = 0u; index < argument->length; ++index) {
        char digit;

        digit = argument->data[index];
        if ((digit < '0') || (digit > '9')) {
            return 0u;
        }

        value = (uint16_t)(
            (value * 10u) +
            (uint16_t)(digit - '0'));

        if (value > (uint16_t)maximum) {
            return 0u;
        }
    }

    *value_out = (uint8_t)value;
    return 1u;
}

/// <summary>
/// Parses a numeric kill signal option such as -2, -9, -18, or -19.
/// </summary>
/// <param name="argument">Signal option argument.</param>
/// <param name="signal_out">Receives the Linux-compatible signal number.</param>
/// <returns>One for a currently implemented signal, otherwise zero.</returns>
static uint8_t kill_parse_signal(
    const neox_arg_t* argument,
    uint8_t* signal_out)
{
    neox_arg_t number_argument;
    uint8_t signal;

    if ((argument->length < 2u) ||
        (argument->data[0] != '-')) {
        return 0u;
    }

    number_argument.data = argument->data + 1;
    number_argument.length = argument->length - 1u;

    if (kill_parse_decimal(
            &number_argument,
            (uint8_t)19u,
            &signal) == 0u) {
        return 0u;
    }

    if ((signal != NEOX_SIG_INT) &&
        (signal != NEOX_SIG_KILL) &&
        (signal != NEOX_SIG_CONT) &&
        (signal != NEOX_SIG_STOP)) {
        return 0u;
    }

    *signal_out = signal;
    return 1u;
}

/// <summary>
/// Executes the numeric-only parent-mode kill applet.
/// </summary>
/// <param name="context">Complete raw applet argument line.</param>
/// <returns>NEOX_STATUS_OK when the signal is accepted, otherwise an error.</returns>
neox_status_t neox_applet_kill(
    const neox_applet_context_t* context)
{
    neox_arg_cursor_t cursor;
    neox_arg_t signal_argument;
    neox_arg_t pid_argument;
    neox_arg_t extra_argument;
    neox_status_t status;
    uint8_t signal;
    uint8_t pid;

    neox_arg_cursor_init(&cursor, context);

    if ((neox_arg_next(&cursor, &signal_argument) == 0u) ||
        (neox_arg_next(&cursor, &pid_argument) == 0u) ||
        (neox_arg_next(&cursor, &extra_argument) != 0u)) {
        neox_applet_report(kill_usage_message);
        return NEOX_STATUS_EINVAL;
    }

    if (kill_parse_signal(&signal_argument, &signal) == 0u) {
        neox_applet_report(kill_invalid_signal_message);
        return NEOX_STATUS_EINVAL;
    }

    if ((kill_parse_decimal(
            &pid_argument,
            (uint8_t)(NEOX_MAX_PROCESSES - 1u),
            &pid) == 0u) ||
        (pid == 0u)) {
        neox_applet_report(kill_invalid_pid_message);
        return NEOX_STATUS_EINVAL;
    }

    status = neox_signal((neox_pid_t)pid, signal);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(kill_failed_message);
    }

    return status;
}
