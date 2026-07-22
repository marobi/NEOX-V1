#include <stdint.h>

#include <neox/applet_support.h>
#include <neox/fs.h>
#include <neox/io.h>
#include <neox/process.h>
#include <neox/status.h>

#include <nbox.h>
#include <neosh_child_entry.h>

#define NEOSH_LINE_MAX ((neox_size_t)64u)
#define NEOSH_PROMPT_MAX ((neox_size_t)64u)

#define NEOSH_REDIR_NONE   ((uint8_t)0u)
#define NEOSH_REDIR_READ   ((uint8_t)1u)
#define NEOSH_REDIR_TRUNC  ((uint8_t)2u)
#define NEOSH_REDIR_APPEND ((uint8_t)3u)

#define NEOSH_FD_CLOSED ((neox_fd_t)0xFFu)

typedef struct neosh_redirection {
    uint8_t mode;
    char path[64];
} neosh_redirection_t;

typedef struct neosh_plan {
    neosh_redirection_t input;
    neosh_redirection_t output;
    neosh_redirection_t error;
    uint8_t redirection_seen;
} neosh_plan_t;

typedef struct neosh_token {
    neox_size_t start;
    neox_size_t length;
} neosh_token_t;

static char neosh_raw_line[64];
static char neosh_prompt[64];
static char neosh_cwd[64];
static char neosh_command[64];

static neox_size_t neosh_prompt_core_length;
static neosh_plan_t neosh_plan;

static neox_fd_t neosh_input_fd;
static neox_fd_t neosh_output_fd;
static neox_fd_t neosh_error_fd;

static char neosh_previous_cwd[64];
static uint8_t neosh_previous_cwd_valid;

static const char neosh_default_prompt[] = "0:/> ";
static const char neosh_redirection_error[] = "REDIR?\r";
static const char neosh_cd_previous_unset[] =
    "cd: previous directory not set\r";
static const char neosh_cd_failure[] =
    "cd: cannot change directory\r";
static const char neosh_cr[] = "\r";
static const char neosh_interrupt_notice[] = "^C\r";

/// <summary>
/// Returns whether one character is shell whitespace.
/// </summary>
/// <param name="value">Character value.</param>
/// <returns>One for space or tab, otherwise zero.</returns>
static uint8_t neosh_is_space(char value)
{
    return (uint8_t)((value == ' ') || (value == '\t'));
}

/// <summary>
/// Writes the current shell prompt through stdout.
/// </summary>
static void neosh_print_prompt(void)
{
    neox_size_t cwd_length;
    neox_status_t status;

    cwd_length = 0u;
    status = neox_getcwd(
        neosh_cwd,
        NEOSH_PROMPT_MAX - 2u,
        &cwd_length);

    if ((status != NEOX_STATUS_OK) ||
        (cwd_length > (NEOSH_PROMPT_MAX - 2u))) {
        neosh_prompt_core_length = 0u;
        (void)neox_applet_write_string(
            NEOX_STDOUT_FD,
            neosh_default_prompt);
        return;
    }

    if (cwd_length != 0u) {
        neox_size_t index;

        for (index = 0u; index < cwd_length; ++index) {
            neosh_prompt[index] = neosh_cwd[index];
        }
    }

    neosh_prompt[cwd_length] = '>';
    neosh_prompt_core_length = cwd_length + 1u;
    neosh_prompt[neosh_prompt_core_length] = ' ';

    (void)neox_applet_write_all(
        NEOX_STDOUT_FD,
        neosh_prompt,
        neosh_prompt_core_length + 1u);
}

/// <summary>
/// Reads one complete VDU-edited input line.
/// </summary>
/// <param name="length_out">Receives the bounded raw byte count.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the read status.</returns>
static neox_status_t neosh_read_line(neox_size_t* length_out)
{
    neox_size_t received;
    neox_status_t status;

    received = 0u;
    status = neox_read(
        NEOX_STDIN_FD,
        neosh_raw_line,
        NEOSH_LINE_MAX - 1u,
        &received);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    if (received >= NEOSH_LINE_MAX) {
        received = NEOSH_LINE_MAX - 1u;
    }

    neosh_raw_line[received] = '\0';
    *length_out = received;
    return NEOX_STATUS_OK;
}

/// <summary>
/// Tests whether the raw line begins with the prompt core.
/// </summary>
/// <param name="raw_length">Raw line byte count.</param>
/// <returns>One when the prefix matches, otherwise zero.</returns>
static uint8_t neosh_line_has_prompt(neox_size_t raw_length)
{
    neox_size_t index;

    if ((neosh_prompt_core_length == 0u) ||
        (neosh_prompt_core_length > raw_length)) {
        return 0u;
    }

    for (index = 0u; index < neosh_prompt_core_length; ++index) {
        if ((char)(neosh_raw_line[index] & 0x7F) != neosh_prompt[index]) {
            return 0u;
        }
    }

    return 1u;
}

/// <summary>
/// Copies one cleaned command line into the nbox input buffer.
/// </summary>
/// <param name="raw_length">Raw input byte count.</param>
static void neosh_clean_line(neox_size_t raw_length)
{
    neox_size_t source;
    neox_size_t destination;

    source = 0u;
    destination = 0u;

    if (neosh_line_has_prompt(raw_length) != 0u) {
        source = neosh_prompt_core_length;
    }

    while ((source < raw_length) &&
           (neosh_is_space((char)(neosh_raw_line[source] & 0x7F)) != 0u)) {
        ++source;
    }

    while ((source < raw_length) &&
           (destination < (NBOX_LINE_MAX - 1u))) {
        char value;

        value = (char)(neosh_raw_line[source] & 0x7F);
        if ((value == '\0') || (value == '\r') || (value == '\n')) {
            break;
        }

        nbox_line_buf[destination] = value;
        ++destination;
        ++source;
    }

    nbox_line_buf[destination] = '\0';
    nbox_line_len = (uint8_t)destination;
}

/// <summary>
/// Clears one redirection plan and temporary descriptor state.
/// </summary>
static void neosh_reset_plan(void)
{
    neosh_plan.input.mode = NEOSH_REDIR_NONE;
    neosh_plan.output.mode = NEOSH_REDIR_NONE;
    neosh_plan.error.mode = NEOSH_REDIR_NONE;

    neosh_plan.input.path[0] = '\0';
    neosh_plan.output.path[0] = '\0';
    neosh_plan.error.path[0] = '\0';
    neosh_plan.redirection_seen = 0u;

    neosh_input_fd = NEOSH_FD_CLOSED;
    neosh_output_fd = NEOSH_FD_CLOSED;
    neosh_error_fd = NEOSH_FD_CLOSED;
}

/// <summary>
/// Reads the next whitespace-delimited token from nbox_line_buf.
/// </summary>
/// <param name="cursor">Current scan position, updated to token end.</param>
/// <param name="token">Receives token start and length.</param>
/// <returns>One when a token was found, otherwise zero.</returns>
static uint8_t neosh_next_token(
    neox_size_t* cursor,
    neosh_token_t* token)
{
    neox_size_t index;

    index = *cursor;
    while ((nbox_line_buf[index] != '\0') &&
           (neosh_is_space(nbox_line_buf[index]) != 0u)) {
        ++index;
    }

    if (nbox_line_buf[index] == '\0') {
        *cursor = index;
        return 0u;
    }

    token->start = index;
    token->length = 0u;

    while ((nbox_line_buf[index] != '\0') &&
           (neosh_is_space(nbox_line_buf[index]) == 0u)) {
        ++token->length;
        ++index;
    }

    *cursor = index;
    return 1u;
}

/// <summary>
/// Classifies a token as a supported redirection operator.
/// </summary>
/// <param name="token">Token to classify.</param>
/// <param name="fd_out">Receives stdin, stdout, or stderr.</param>
/// <param name="mode_out">Receives the redirection mode.</param>
/// <param name="operator_length_out">Receives the operator byte count.</param>
/// <returns>One when classified as redirection, otherwise zero.</returns>
static uint8_t neosh_classify_redirection(
    const neosh_token_t* token,
    neox_fd_t* fd_out,
    uint8_t* mode_out,
    neox_size_t* operator_length_out)
{
    neox_size_t start;

    start = token->start;

    if (nbox_line_buf[start] == '<') {
        *fd_out = NEOX_STDIN_FD;
        *mode_out = NEOSH_REDIR_READ;
        *operator_length_out = 1u;
        return 1u;
    }

    if (nbox_line_buf[start] == '>') {
        *fd_out = NEOX_STDOUT_FD;
        *mode_out = NEOSH_REDIR_TRUNC;
        *operator_length_out = 1u;

        if ((token->length >= 2u) &&
            (nbox_line_buf[start + 1u] == '>')) {
            *mode_out = NEOSH_REDIR_APPEND;
            *operator_length_out = 2u;
        }

        return 1u;
    }

    if ((nbox_line_buf[start] == '2') &&
        (token->length >= 2u) &&
        (nbox_line_buf[start + 1u] == '>')) {
        *fd_out = NEOX_STDERR_FD;
        *mode_out = NEOSH_REDIR_TRUNC;
        *operator_length_out = 2u;

        if ((token->length >= 3u) &&
            (nbox_line_buf[start + 2u] == '>')) {
            *mode_out = NEOSH_REDIR_APPEND;
            *operator_length_out = 3u;
        }

        return 1u;
    }

    return 0u;
}

/// <summary>
/// Selects the redirection record for one standard descriptor.
/// </summary>
/// <param name="fd">Standard descriptor.</param>
/// <returns>Record address, or null for an invalid descriptor.</returns>
static neosh_redirection_t* neosh_redirection_for_fd(neox_fd_t fd)
{
    if (fd == NEOX_STDIN_FD) {
        return &neosh_plan.input;
    }

    if (fd == NEOX_STDOUT_FD) {
        return &neosh_plan.output;
    }

    if (fd == NEOX_STDERR_FD) {
        return &neosh_plan.error;
    }

    return (neosh_redirection_t*)0;
}

/// <summary>
/// Stores one bounded pathname in a redirection record.
/// </summary>
/// <param name="record">Destination redirection record.</param>
/// <param name="mode">Requested redirection mode.</param>
/// <param name="start">Path start in nbox_line_buf.</param>
/// <param name="length">Path byte count.</param>
/// <returns>One on success, otherwise zero.</returns>
static uint8_t neosh_store_redirection(
    neosh_redirection_t* record,
    uint8_t mode,
    neox_size_t start,
    neox_size_t length)
{
    neox_size_t index;

    if ((record == (neosh_redirection_t*)0) ||
        (record->mode != NEOSH_REDIR_NONE) ||
        (length == 0u) ||
        (length >= NEOSH_LINE_MAX)) {
        return 0u;
    }

    for (index = 0u; index < length; ++index) {
        record->path[index] = nbox_line_buf[start + index];
    }

    record->path[length] = '\0';
    record->mode = mode;
    neosh_plan.redirection_seen = 1u;
    return 1u;
}

/// <summary>
/// Appends one ordinary token to the compact command line.
/// </summary>
/// <param name="token">Token to append.</param>
/// <param name="destination">Current output position.</param>
/// <returns>One on success, otherwise zero.</returns>
static uint8_t neosh_append_command_token(
    const neosh_token_t* token,
    neox_size_t* destination)
{
    neox_size_t index;

    if (*destination != 0u) {
        if (*destination >= (NEOSH_LINE_MAX - 1u)) {
            return 0u;
        }

        neosh_command[*destination] = ' ';
        ++(*destination);
    }

    if ((*destination + token->length) >= NEOSH_LINE_MAX) {
        return 0u;
    }

    for (index = 0u; index < token->length; ++index) {
        neosh_command[*destination] =
            nbox_line_buf[token->start + index];
        ++(*destination);
    }

    return 1u;
}

/// <summary>
/// Parses and removes shell redirection tokens.
/// </summary>
/// <returns>One for a valid plan, otherwise zero.</returns>
static uint8_t neosh_parse_redirections(void)
{
    neox_size_t cursor;
    neox_size_t destination;
    neosh_token_t token;

    neosh_reset_plan();
    cursor = 0u;
    destination = 0u;

    while (neosh_next_token(&cursor, &token) != 0u) {
        neox_fd_t fd;
        uint8_t mode;
        neox_size_t operator_length;

        if (neosh_classify_redirection(
                &token,
                &fd,
                &mode,
                &operator_length) != 0u) {
            neox_size_t path_start;
            neox_size_t path_length;
            neosh_redirection_t* record;

            record = neosh_redirection_for_fd(fd);

            if (token.length > operator_length) {
                path_start = token.start + operator_length;
                path_length = token.length - operator_length;
            } else {
                neosh_token_t path_token;
                neox_fd_t ignored_fd;
                uint8_t ignored_mode;
                neox_size_t ignored_length;

                if (neosh_next_token(&cursor, &path_token) == 0u) {
                    return 0u;
                }

                if (neosh_classify_redirection(
                        &path_token,
                        &ignored_fd,
                        &ignored_mode,
                        &ignored_length) != 0u) {
                    return 0u;
                }

                path_start = path_token.start;
                path_length = path_token.length;
            }

            if (neosh_store_redirection(
                    record,
                    mode,
                    path_start,
                    path_length) == 0u) {
                return 0u;
            }
        } else {
            if (neosh_append_command_token(
                    &token,
                    &destination) == 0u) {
                return 0u;
            }
        }
    }

    if ((destination == 0u) &&
        (neosh_plan.redirection_seen != 0u)) {
        return 0u;
    }

    neosh_command[destination] = '\0';

    {
        neox_size_t index;

        for (index = 0u; index <= destination; ++index) {
            nbox_line_buf[index] = neosh_command[index];
        }
    }

    nbox_line_len = (uint8_t)destination;
    return 1u;
}

/// <summary>
/// Closes all temporary parent redirection descriptors.
/// </summary>
static void neosh_close_redirections(void)
{
    if (neosh_input_fd != NEOSH_FD_CLOSED) {
        (void)neox_close(neosh_input_fd);
        neosh_input_fd = NEOSH_FD_CLOSED;
    }

    if (neosh_output_fd != NEOSH_FD_CLOSED) {
        (void)neox_close(neosh_output_fd);
        neosh_output_fd = NEOSH_FD_CLOSED;
    }

    if (neosh_error_fd != NEOSH_FD_CLOSED) {
        (void)neox_close(neosh_error_fd);
        neosh_error_fd = NEOSH_FD_CLOSED;
    }
}

/// <summary>
/// Opens one redirection and records the parent descriptor.
/// </summary>
/// <param name="fd">Target standard descriptor.</param>
/// <param name="record">Redirection record.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure.</returns>
static neox_status_t neosh_open_redirection(
    neox_fd_t fd,
    const neosh_redirection_t* record)
{
    neox_open_mode_t open_mode;
    neox_fd_t opened_fd;
    neox_status_t status;

    if (record->mode == NEOSH_REDIR_READ) {
        if (fd != NEOX_STDIN_FD) {
            return NEOX_STATUS_EINVAL;
        }

        open_mode = NEOX_OPEN_READ;
    } else if (record->mode == NEOSH_REDIR_TRUNC) {
        if ((fd != NEOX_STDOUT_FD) &&
            (fd != NEOX_STDERR_FD)) {
            return NEOX_STATUS_EINVAL;
        }

        open_mode = NEOX_OPEN_WRITE_TRUNC;
    } else if (record->mode == NEOSH_REDIR_APPEND) {
        if ((fd != NEOX_STDOUT_FD) &&
            (fd != NEOX_STDERR_FD)) {
            return NEOX_STATUS_EINVAL;
        }

        open_mode = NEOX_OPEN_READ_WRITE_CREATE;
    } else {
        return NEOX_STATUS_EINVAL;
    }

    opened_fd = NEOSH_FD_CLOSED;
    status = neox_open(record->path, open_mode, &opened_fd);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    if (record->mode == NEOSH_REDIR_APPEND) {
        status = neox_seek(
            opened_fd,
            (int32_t)0,
            NEOX_SEEK_END,
            (uint32_t*)0);
        if (status != NEOX_STATUS_OK) {
            (void)neox_close(opened_fd);
            return status;
        }
    }

    if (fd == NEOX_STDIN_FD) {
        neosh_input_fd = opened_fd;
    } else if (fd == NEOX_STDOUT_FD) {
        neosh_output_fd = opened_fd;
    } else {
        neosh_error_fd = opened_fd;
    }

    return NEOX_STATUS_OK;
}

/// <summary>
/// Opens all requested redirections transactionally.
/// </summary>
/// <returns>NEOX_STATUS_OK on success, otherwise the first failure.</returns>
static neox_status_t neosh_open_redirections(void)
{
    neox_status_t status;

    if (neosh_plan.input.mode != NEOSH_REDIR_NONE) {
        status = neosh_open_redirection(
            NEOX_STDIN_FD,
            &neosh_plan.input);
        if (status != NEOX_STATUS_OK) {
            neosh_close_redirections();
            return status;
        }
    }

    if (neosh_plan.output.mode != NEOSH_REDIR_NONE) {
        status = neosh_open_redirection(
            NEOX_STDOUT_FD,
            &neosh_plan.output);
        if (status != NEOX_STATUS_OK) {
            neosh_close_redirections();
            return status;
        }
    }

    if (neosh_plan.error.mode != NEOSH_REDIR_NONE) {
        status = neosh_open_redirection(
            NEOX_STDERR_FD,
            &neosh_plan.error);
        if (status != NEOX_STATUS_OK) {
            neosh_close_redirections();
            return status;
        }
    }

    return NEOX_STATUS_OK;
}

/// <summary>
/// Spawns the currently resolved child and waits for completion.
/// </summary>
/// <returns>NEOX_STATUS_OK on success, otherwise spawn/wait status.</returns>
static neox_status_t neosh_execute_child(void)
{
    neox_spawn_resident_args_t spawn_args;
    neox_size_t argument_start;
    neox_size_t argument_length;
    neox_pid_t child_pid;
    uint8_t child_exit_status;
    neox_status_t status;

    argument_start = nbox_line_idx;
    while ((nbox_line_buf[argument_start] != '\0') &&
           (neosh_is_space(nbox_line_buf[argument_start]) != 0u)) {
        ++argument_start;
    }

    argument_length = neox_applet_string_length(
        &nbox_line_buf[argument_start]);

    spawn_args.entry = neosh_nbox_child_entry;
    spawn_args.launch_id = nbox_launch_id;
    spawn_args.argument_line = &nbox_line_buf[argument_start];
    spawn_args.argument_length = (uint8_t)argument_length;

    spawn_args.stdin_fd =
        (neosh_input_fd == NEOSH_FD_CLOSED)
            ? NEOX_STDIN_FD
            : neosh_input_fd;

    spawn_args.stdout_fd =
        (neosh_output_fd == NEOSH_FD_CLOSED)
            ? NEOX_STDOUT_FD
            : neosh_output_fd;

    spawn_args.stderr_fd =
        (neosh_error_fd == NEOSH_FD_CLOSED)
            ? NEOX_STDERR_FD
            : neosh_error_fd;

    spawn_args.flags = NEOX_PROC_FLAG_FOREGROUND;
    spawn_args.result_pid = (neox_pid_t)0xFFu;

    child_pid = (neox_pid_t)0xFFu;
    status = neox_spawn_resident(&spawn_args, &child_pid);
    if (status == NEOX_STATUS_OK) {
        child_exit_status = 0u;
        status = neox_waitpid(child_pid, &child_exit_status);
    }

    neosh_close_redirections();

    if ((status == NEOX_STATUS_OK) &&
        (child_exit_status == (uint8_t)0xFEu)) {
        (void)neox_applet_write_string(
            NEOX_STDOUT_FD,
            neosh_interrupt_notice);
    }

    return status;
}

/// <summary>
/// Returns whether the resolved cd command has exactly the argument "-".
/// </summary>
/// <returns>One for exactly `cd -`, otherwise zero.</returns>
static uint8_t neosh_is_cd_dash(void)
{
    neox_size_t index;

    index = nbox_line_idx;
    while ((nbox_line_buf[index] != '\0') &&
           (neosh_is_space(nbox_line_buf[index]) != 0u)) {
        ++index;
    }

    if (nbox_line_buf[index] != '-') {
        return 0u;
    }

    ++index;
    while ((nbox_line_buf[index] != '\0') &&
           (neosh_is_space(nbox_line_buf[index]) != 0u)) {
        ++index;
    }

    return (uint8_t)(nbox_line_buf[index] == '\0');
}

/// <summary>
/// Copies one NUL-terminated path into a fixed shell buffer.
/// </summary>
/// <param name="destination">Destination path buffer.</param>
/// <param name="source">NUL-terminated source path.</param>
static void neosh_copy_path(
    char* destination,
    const char* source)
{
    neox_size_t index;

    index = 0u;
    while ((index < (NEOX_PATH_MAX - 1u)) &&
           (source[index] != '\0')) {
        destination[index] = source[index];
        ++index;
    }

    destination[index] = '\0';
}

/// <summary>
/// Executes shell-owned `cd -` previous-directory switching.
/// </summary>
/// <returns>NEOX_STATUS_OK on success, otherwise the filesystem status.</returns>
static neox_status_t neosh_execute_cd_dash(void)
{
    char current_cwd[64];
    neox_size_t current_length;
    neox_status_t status;

    if (neosh_previous_cwd_valid == 0u) {
        neox_applet_report(neosh_cd_previous_unset);
        return NEOX_STATUS_EINVAL;
    }

    current_length = 0u;
    status = neox_getcwd(
        current_cwd,
        NEOX_PATH_MAX,
        &current_length);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(neosh_cd_failure);
        return status;
    }

    status = neox_chdir(neosh_previous_cwd);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(neosh_cd_failure);
        return status;
    }

    neosh_copy_path(neosh_previous_cwd, current_cwd);
    neosh_previous_cwd_valid = 1u;

    current_length = 0u;
    status = neox_getcwd(
        current_cwd,
        NEOX_PATH_MAX,
        &current_length);
    if (status != NEOX_STATUS_OK) {
        neox_applet_report(neosh_cd_failure);
        return status;
    }

    status = neox_applet_write_all(
        NEOX_STDOUT_FD,
        current_cwd,
        current_length);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    return neox_applet_write_all(
        NEOX_STDOUT_FD,
        neosh_cr,
        (neox_size_t)1u);
}

/// <summary>
/// Executes the normal parent-mode cd applet and records the old cwd on success.
/// </summary>
/// <returns>The applet status.</returns>
static neox_status_t neosh_execute_cd_parent(void)
{
    char old_cwd[64];
    neox_size_t old_length;
    neox_status_t status;

    old_length = 0u;
    status = neox_getcwd(
        old_cwd,
        NEOX_PATH_MAX,
        &old_length);
    if (status != NEOX_STATUS_OK) {
        return status;
    }

    status = neosh_nbox_dispatch();
    if (status == NEOX_STATUS_OK) {
        neosh_copy_path(neosh_previous_cwd, old_cwd);
        neosh_previous_cwd_valid = 1u;
    }

    return status;
}

/// <summary>
/// Resolves and executes the compact command line.
/// </summary>
static void neosh_execute_line(void)
{
    neox_status_t status;

    if (neosh_nbox_resolve() != 0u) {
        (void)neosh_nbox_print_unknown();
        return;
    }

    if (nbox_exec_mode == NBOX_EXEC_NONE) {
        return;
    }

    if (nbox_exec_mode == NBOX_EXEC_PARENT) {
        if (neosh_plan.redirection_seen != 0u) {
            (void)neox_applet_write_string(
                NEOX_STDOUT_FD,
                neosh_redirection_error);
            return;
        }

        if (nbox_launch_id == NBOX_APPLET_CD) {
            if (neosh_is_cd_dash() != 0u) {
                (void)neosh_execute_cd_dash();
            } else {
                (void)neosh_execute_cd_parent();
            }

            return;
        }

        (void)neosh_nbox_dispatch();
        return;
    }

    if (nbox_exec_mode != NBOX_EXEC_CHILD) {
        (void)neosh_nbox_print_unknown();
        return;
    }

    if (neosh_plan.redirection_seen != 0u) {
        status = neosh_open_redirections();
        if (status != NEOX_STATUS_OK) {
            (void)neox_applet_write_string(
                NEOX_STDOUT_FD,
                neosh_redirection_error);
            return;
        }
    }

    status = neosh_execute_child();
    if (status != NEOX_STATUS_OK) {
        if (neosh_plan.redirection_seen != 0u) {
            (void)neox_applet_write_string(
                NEOX_STDOUT_FD,
                neosh_redirection_error);
        } else {
            (void)neosh_nbox_print_unknown();
        }
    }
}

/// <summary>
/// Runs the interactive NEOX shell loop.
/// </summary>
void neosh_main(void)
{
    for (;;) {
        neox_size_t raw_length;

        neosh_print_prompt();

        for (;;) {
            neox_status_t read_status;

            read_status = neosh_read_line(&raw_length);
            if (read_status == NEOX_STATUS_OK) {
                break;
            }

            if (read_status == NEOX_STATUS_EINTR) {
                neosh_raw_line[0] = '\0';
                nbox_line_buf[0] = '\0';
                nbox_line_len = 0u;
                (void)neox_applet_write_string(
                    NEOX_STDOUT_FD,
                    neosh_interrupt_notice);
                raw_length = 0u;
                break;
            }
        }

        if (raw_length == 0u) {
            continue;
        }

        neosh_clean_line(raw_length);

        if (neosh_parse_redirections() == 0u) {
            (void)neox_applet_write_string(
                NEOX_STDOUT_FD,
                neosh_redirection_error);
            continue;
        }

        neosh_execute_line();
    }
}
