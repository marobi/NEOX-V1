#ifndef NEOX_SIGNAL_H
#define NEOX_SIGNAL_H

#include <stdint.h>

#include <neox/types.h>

#define NEOX_SIG_INT  ((uint8_t)2u)
#define NEOX_SIG_KILL ((uint8_t)9u)
#define NEOX_SIG_CONT ((uint8_t)18u)
#define NEOX_SIG_STOP ((uint8_t)19u)

/// <summary>
/// Sends one implemented Linux-compatible signal number to a process.
/// </summary>
/// <param name="pid">Target process ID.</param>
/// <param name="signal">NEOX_SIG_INT, NEOX_SIG_KILL, NEOX_SIG_CONT, or NEOX_SIG_STOP.</param>
/// <returns>NEOX_STATUS_OK when accepted, otherwise a NEOX error code.</returns>
neox_status_t neox_signal(
    neox_pid_t pid,
    uint8_t signal);

#endif /* NEOX_SIGNAL_H */
