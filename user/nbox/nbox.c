#include <stdint.h>

#include <neox/applet.h>
#include <neox/applet_support.h>
#include <neox/status.h>

#include <nbox.h>

#define NBOX_COMMAND_COUNT ((uint8_t)12u)
#define NBOX_COMMAND_MAX   ((neox_size_t)6u)

typedef neox_status_t (*nbox_applet_t)(
    const neox_applet_context_t* context);

typedef struct nbox_command {
    const char* name;
    uint8_t launch_id;
    uint8_t execution_mode;
    nbox_applet_t applet;
} nbox_command_t;

char nbox_line_buf[64];
uint8_t nbox_line_len;
uint8_t nbox_exec_mode;
uint8_t nbox_launch_id;
uint8_t nbox_line_idx;

static uint8_t nbox_command_index;

static const char nbox_unknown_message[] =
    "nbox: command not found\r";

neox_status_t neox_applet_pwd(const neox_applet_context_t* context);
neox_status_t neox_applet_cd(const neox_applet_context_t* context);
neox_status_t neox_applet_ls(const neox_applet_context_t* context);
neox_status_t neox_applet_cat(const neox_applet_context_t* context);
neox_status_t neox_applet_echo(const neox_applet_context_t* context);
neox_status_t neox_applet_rm(const neox_applet_context_t* context);
neox_status_t neox_applet_mv(const neox_applet_context_t* context);
neox_status_t neox_applet_mkdir(const neox_applet_context_t* context);
neox_status_t neox_applet_rmdir(const neox_applet_context_t* context);
neox_status_t neox_applet_cp(const neox_applet_context_t* context);
neox_status_t neox_applet_ps(const neox_applet_context_t* context);
neox_status_t neox_applet_kill(const neox_applet_context_t* context);

static const nbox_command_t nbox_commands[NBOX_COMMAND_COUNT] = {
    {
        "PWD",
        NBOX_APPLET_PWD,
        NBOX_EXEC_CHILD,
        neox_applet_pwd
    },
    {
        "CD",
        NBOX_APPLET_CD,
        NBOX_EXEC_PARENT,
        neox_applet_cd
    },
    {
        "LS",
        NBOX_APPLET_LS,
        NBOX_EXEC_CHILD,
        neox_applet_ls
    },
    {
        "CAT",
        NBOX_APPLET_CAT,
        NBOX_EXEC_CHILD,
        neox_applet_cat
    },
    {
        "ECHO",
        NBOX_APPLET_ECHO,
        NBOX_EXEC_CHILD,
        neox_applet_echo
    },
    {
        "RM",
        NBOX_APPLET_RM,
        NBOX_EXEC_CHILD,
        neox_applet_rm
    },
    {
        "MV",
        NBOX_APPLET_MV,
        NBOX_EXEC_CHILD,
        neox_applet_mv
    },
    {
        "MKDIR",
        NBOX_APPLET_MKDIR,
        NBOX_EXEC_CHILD,
        neox_applet_mkdir
    },
    {
        "RMDIR",
        NBOX_APPLET_RMDIR,
        NBOX_EXEC_CHILD,
        neox_applet_rmdir
    },
    {
        "CP",
        NBOX_APPLET_CP,
        NBOX_EXEC_CHILD,
        neox_applet_cp
    },
    {
        "PS",
        NBOX_APPLET_PS,
        NBOX_EXEC_CHILD,
        neox_applet_ps
    },
    {
        "KILL",
        NBOX_APPLET_KILL,
        NBOX_EXEC_PARENT,
        neox_applet_kill
    }
};

/// <summary>
/// Returns whether one byte is command whitespace.
/// </summary>
/// <param name="value">Character value.</param>
/// <returns>One for space or tab, otherwise zero.</returns>
static uint8_t nbox_is_space(char value)
{
    return (uint8_t)((value == ' ') || (value == '\t'));
}

/// <summary>
/// Converts one ASCII byte to uppercase without changing other bytes.
/// </summary>
/// <param name="value">Input byte.</param>
/// <returns>Uppercase ASCII byte.</returns>
static char nbox_upper(char value)
{
    value = (char)(value & 0x7F);

    if ((value >= 'a') && (value <= 'z')) {
        value = (char)(value - ('a' - 'A'));
    }

    return value;
}

/// <summary>
/// Compares one command token with a zero-terminated uppercase name.
/// </summary>
/// <param name="start">Token start in nbox_line_buf.</param>
/// <param name="length">Token length.</param>
/// <param name="name">Expected uppercase command name.</param>
/// <returns>One on match, otherwise zero.</returns>
static uint8_t nbox_token_matches(
    neox_size_t start,
    neox_size_t length,
    const char* name)
{
    neox_size_t index;

    index = 0u;
    while (index < length) {
        if (name[index] == '\0') {
            return 0u;
        }

        if (nbox_upper(nbox_line_buf[start + index]) != name[index]) {
            return 0u;
        }

        ++index;
    }

    return (uint8_t)(name[index] == '\0');
}

/// <summary>
/// Builds an applet context from the current nbox line.
/// </summary>
/// <param name="start">First possible argument byte.</param>
/// <param name="context">Destination applet context.</param>
static void nbox_make_context(
    neox_size_t start,
    neox_applet_context_t* context)
{
    while ((start < nbox_line_len) &&
           (nbox_is_space(nbox_line_buf[start]) != 0u)) {
        ++start;
    }

    context->line = &nbox_line_buf[start];
    context->line_length = (neox_size_t)(nbox_line_len - start);
}

/// <summary>
/// Returns the command-table index for one launch ID.
/// </summary>
/// <param name="launch_id">Stable resident applet selector.</param>
/// <returns>Command index, or NBOX_COMMAND_COUNT when not found.</returns>
static uint8_t nbox_find_launch_id(uint8_t launch_id)
{
    uint8_t index;

    for (index = 0u; index < NBOX_COMMAND_COUNT; ++index) {
        if (nbox_commands[index].launch_id == launch_id) {
            return index;
        }
    }

    return NBOX_COMMAND_COUNT;
}

/// <summary>
/// Calls one applet through its command-table entry.
/// </summary>
/// <param name="command_index">Validated command-table index.</param>
/// <param name="context">Applet argument context.</param>
/// <returns>The selected applet status.</returns>
static neox_status_t nbox_call_command(
    uint8_t command_index,
    const neox_applet_context_t* context)
{
    if (command_index >= NBOX_COMMAND_COUNT) {
        (void)neosh_nbox_print_unknown();
        return NEOX_STATUS_EINVAL;
    }

    return nbox_commands[command_index].applet(context);
}

/// <summary>
/// Resolves the command stored in nbox_line_buf.
/// </summary>
/// <returns>Zero when resolved or empty; nonzero when unknown.</returns>
uint8_t neosh_nbox_resolve(void)
{
    neox_size_t start;
    neox_size_t end;
    neox_size_t length;
    uint8_t command_index;

    nbox_exec_mode = NBOX_EXEC_UNKNOWN;
    nbox_launch_id = NBOX_APPLET_NONE;
    nbox_line_idx = 0u;
    nbox_command_index = NBOX_COMMAND_COUNT;

    start = 0u;
    while ((start < nbox_line_len) &&
           (nbox_is_space(nbox_line_buf[start]) != 0u)) {
        ++start;
    }

    if ((start >= nbox_line_len) ||
        (nbox_line_buf[start] == '\0')) {
        nbox_exec_mode = NBOX_EXEC_NONE;
        return 0u;
    }

    end = start;
    while ((end < nbox_line_len) &&
           (nbox_line_buf[end] != '\0') &&
           (nbox_is_space(nbox_line_buf[end]) == 0u)) {
        ++end;
    }

    length = end - start;
    nbox_line_idx = (uint8_t)end;

    if ((length == 0u) || (length > NBOX_COMMAND_MAX)) {
        return 1u;
    }

    for (command_index = 0u;
         command_index < NBOX_COMMAND_COUNT;
         ++command_index) {
        if (nbox_token_matches(
                start,
                length,
                nbox_commands[command_index].name) != 0u) {
            nbox_command_index = command_index;
            nbox_launch_id =
                nbox_commands[command_index].launch_id;
            nbox_exec_mode =
                nbox_commands[command_index].execution_mode;
            return 0u;
        }
    }

    return 1u;
}

/// <summary>
/// Executes the currently resolved command in the current process.
/// </summary>
/// <returns>The applet status.</returns>
neox_status_t neosh_nbox_dispatch(void)
{
    neox_applet_context_t context;

    if (nbox_exec_mode == NBOX_EXEC_NONE) {
        return NEOX_STATUS_OK;
    }

    if ((nbox_exec_mode == NBOX_EXEC_UNKNOWN) ||
        (nbox_launch_id == NBOX_APPLET_NONE)) {
        (void)neosh_nbox_print_unknown();
        return NEOX_STATUS_EINVAL;
    }

    nbox_make_context((neox_size_t)nbox_line_idx, &context);
    return nbox_call_command(nbox_command_index, &context);
}

/// <summary>
/// Writes the standard unknown-command diagnostic to stderr.
/// </summary>
/// <returns>Always zero.</returns>
uint8_t neosh_nbox_print_unknown(void)
{
    neox_applet_report(nbox_unknown_message);
    return 0u;
}

/// <summary>
/// Executes one resident applet selected by launch ID.
/// </summary>
/// <param name="launch_id">Resident applet launch selector.</param>
/// <returns>The applet status.</returns>
neox_status_t __fastcall__ nbox_execute_launch_id(uint8_t launch_id)
{
    neox_applet_context_t context;

    uint8_t command_index;

    command_index = nbox_find_launch_id(launch_id);
    nbox_make_context(0u, &context);
    return nbox_call_command(command_index, &context);
}
