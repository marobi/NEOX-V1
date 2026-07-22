#ifndef NEOX_IO_H
#define NEOX_IO_H

#include <stdint.h>

#include <neox/types.h>

#define NEOX_STDIN_FD  ((neox_fd_t)0u)
#define NEOX_STDOUT_FD ((neox_fd_t)1u)
#define NEOX_STDERR_FD ((neox_fd_t)2u)

#define NEOX_PATH_MAX ((neox_size_t)64u)

typedef enum neox_open_mode {
    NEOX_OPEN_READ = 0u,
    NEOX_OPEN_WRITE_TRUNC = 1u,
    NEOX_OPEN_WRITE_EXISTING = 2u,
    NEOX_OPEN_READ_WRITE_EXISTING = 3u,
    NEOX_OPEN_READ_WRITE_CREATE = 4u
} neox_open_mode_t;

/// <summary>
/// Opens a filesystem path and returns a process descriptor.
/// </summary>
/// <param name="path">NUL-terminated pathname.</param>
/// <param name="mode">Requested open mode.</param>
/// <param name="fd_out">Receives the opened descriptor. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_open(
    const char* path,
    neox_open_mode_t mode,
    neox_fd_t* fd_out);

/// <summary>
/// Reads bytes from a NEOX descriptor.
/// </summary>
/// <param name="fd">Source descriptor.</param>
/// <param name="buffer">Destination buffer.</param>
/// <param name="requested">Maximum number of bytes requested.</param>
/// <param name="read_out">Receives the number of bytes read. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_read(
    neox_fd_t fd,
    void* buffer,
    neox_size_t requested,
    neox_size_t* read_out);

/// <summary>
/// Writes bytes to a NEOX descriptor.
/// </summary>
/// <param name="fd">Destination descriptor.</param>
/// <param name="buffer">Pointer to the bytes to write.</param>
/// <param name="requested">Number of bytes requested.</param>
/// <param name="written_out">Receives the number of bytes written. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_write(
    neox_fd_t fd,
    const void* buffer,
    neox_size_t requested,
    neox_size_t* written_out);


typedef enum neox_seek_whence {
    NEOX_SEEK_SET = 0u,
    NEOX_SEEK_CUR = 1u,
    NEOX_SEEK_END = 2u
} neox_seek_whence_t;

/// <summary>
/// Repositions one open descriptor.
/// </summary>
/// <param name="fd">Descriptor to reposition.</param>
/// <param name="offset">Signed byte offset.</param>
/// <param name="whence">Reference position.</param>
/// <param name="position_out">Receives the resulting absolute position. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_seek(
    neox_fd_t fd,
    int32_t offset,
    neox_seek_whence_t whence,
    uint32_t* position_out);

/// <summary>
/// Closes a NEOX descriptor.
/// </summary>
/// <param name="fd">Descriptor to close.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_close(neox_fd_t fd);

#endif /* NEOX_IO_H */
