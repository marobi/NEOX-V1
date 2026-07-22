#ifndef NEOX_PROCESS_H
#define NEOX_PROCESS_H

#include <stdint.h>

#include <neox/types.h>


#define NEOX_SPAWN_LINE_MAX ((neox_size_t)64u)
#define NEOX_PROC_FLAGS_NONE             ((uint8_t)0x00u)
#define NEOX_PROC_FLAG_ATTACHED_CON       ((uint8_t)0x02u)
#define NEOX_PROC_FLAG_FOREGROUND         ((uint8_t)0x04u)
#define NEOX_PROC_FLAG_SIGINT_INTERRUPT   ((uint8_t)0x08u)
#define NEOX_SPAWN_LAUNCH_NONE ((uint8_t)0xFFu)
#define NEOX_SPAWN_FD_CLOSED ((neox_fd_t)0xFFu)

typedef void (*neox_process_entry_t)(void);

typedef struct neox_spawn_resident_args {
    neox_process_entry_t entry;
    uint8_t launch_id;
    const char* argument_line;
    uint8_t argument_length;
    neox_fd_t stdin_fd;
    neox_fd_t stdout_fd;
    neox_fd_t stderr_fd;
    uint8_t flags;
    neox_pid_t result_pid;
} neox_spawn_resident_args_t;

typedef char neox_spawn_resident_args_size_must_be_11[
    (sizeof(neox_spawn_resident_args_t) == 11u) ? 1 : -1];

/// <summary>
/// Creates and publishes one resident-image child process. The existing
/// flags field supplies the child's initial proc_flags. Setting
/// NEOX_PROC_FLAG_FOREGROUND transfers console ownership from the current
/// owning parent to the child until it is reaped. Process flags are explicit
/// and are not inherited from the parent.
/// </summary>
/// <param name="args">Mutable resident-spawn argument block.</param>
/// <param name="pid_out">Receives the created child PID. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_spawn_resident(
    neox_spawn_resident_args_t* args,
    neox_pid_t* pid_out);

/// <summary>
/// Waits for and reaps one child process.
/// </summary>
/// <param name="pid">Child PID.</param>
/// <param name="exit_status_out">Receives the child exit status. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_waitpid(
    neox_pid_t pid,
    uint8_t* exit_status_out);

/// <summary>
/// Retrieves the active process resident launch selector.
/// </summary>
/// <param name="launch_id_out">Receives the launch selector. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_get_launch_id(uint8_t* launch_id_out);

/// <summary>
/// Retrieves the active process opaque launch line.
/// </summary>
/// <param name="buffer">Destination buffer.</param>
/// <param name="buffer_size">Buffer capacity including the terminating NUL.</param>
/// <param name="length_out">Receives the copied length excluding NUL. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_get_launch_line(
    char* buffer,
    neox_size_t buffer_size,
    neox_size_t* length_out);

#define NEOX_MAX_PROCESSES ((neox_pid_t)8u)

#define NEOX_PROCESS_EMPTY   ((uint8_t)0u)
#define NEOX_PROCESS_NEW     ((uint8_t)1u)
#define NEOX_PROCESS_READY   ((uint8_t)2u)
#define NEOX_PROCESS_RUNNING ((uint8_t)3u)
#define NEOX_PROCESS_BLOCKED ((uint8_t)4u)
#define NEOX_PROCESS_STOPPED ((uint8_t)5u)
#define NEOX_PROCESS_ZOMBIE  ((uint8_t)6u)

#define NEOX_WAIT_NONE       ((uint8_t)0u)
#define NEOX_WAIT_CONSOLE    ((uint8_t)1u)
#define NEOX_WAIT_DEVICE     ((uint8_t)2u)
#define NEOX_WAIT_PIPE_READ  ((uint8_t)3u)
#define NEOX_WAIT_TIMER      ((uint8_t)4u)
#define NEOX_WAIT_PROCESS    ((uint8_t)5u)
#define NEOX_WAIT_LOCK       ((uint8_t)6u)
#define NEOX_WAIT_PIPE_WRITE ((uint8_t)7u)
#define NEOX_WAIT_RP         ((uint8_t)8u)

#define NEOX_LOCK_FILE_IO ((uint8_t)0u)
#define NEOX_LOCK_PROCESS ((uint8_t)1u)

#define NEOX_PROCESS_HOLD_NONE    ((uint8_t)0u)
#define NEOX_PROCESS_HOLD_FILE_IO ((uint8_t)1u)
#define NEOX_PROCESS_HOLD_PROCESS ((uint8_t)2u)

typedef struct neox_process_info {
    neox_pid_t pid;
    neox_pid_t parent_pid;
    uint8_t state;
    uint8_t wait_reason;
    uint8_t signal_pending;
    uint8_t wait_object;
    uint8_t held_gate_mask;
} neox_process_info_t;

/// <summary>
/// Retrieves one process-table snapshot record.
/// </summary>
/// <param name="pid">Process slot to query.</param>
/// <param name="info">Destination process-information record.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_get_process_info(
    neox_pid_t pid,
    neox_process_info_t* info);

#endif /* NEOX_PROCESS_H */
