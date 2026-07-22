#ifndef NEOX_FS_H
#define NEOX_FS_H

#include <neox/types.h>

/// <summary>
/// Removes one filesystem file.
/// </summary>
/// <param name="path">NUL-terminated pathname.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_delete(const char* path);

/// <summary>
/// Creates one filesystem directory.
/// </summary>
/// <param name="path">NUL-terminated pathname.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_mkdir(const char* path);

/// <summary>
/// Removes one empty filesystem directory.
/// </summary>
/// <param name="path">NUL-terminated pathname.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_rmdir(const char* path);

/// <summary>
/// Renames or moves one filesystem path.
/// </summary>
/// <param name="old_path">Existing source pathname.</param>
/// <param name="new_path">Destination pathname.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_rename(
    const char* old_path,
    const char* new_path);

/// <summary>
/// Changes the current process directory.
/// </summary>
/// <param name="path">NUL-terminated directory pathname.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_chdir(const char* path);

/// <summary>
/// Retrieves the current process directory.
/// </summary>
/// <param name="buffer">Destination buffer for the NUL-terminated path.</param>
/// <param name="buffer_size">Capacity of the destination buffer.</param>
/// <param name="length_out">Receives the path length excluding NUL. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_getcwd(
    char* buffer,
    neox_size_t buffer_size,
    neox_size_t* length_out);


#define NEOX_DIR_NAME_SIZE ((neox_size_t)13u)
#define NEOX_FILE_ATTRIBUTE_DIRECTORY ((uint8_t)0x10u)

typedef struct neox_dir_entry {
    char name[13];
    uint8_t attributes;
    uint32_t size;
} neox_dir_entry_t;

/// <summary>
/// Opens a filesystem directory.
/// </summary>
/// <param name="path">NUL-terminated directory pathname.</param>
/// <param name="fd_out">Receives the opened directory descriptor. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_opendir(
    const char* path,
    neox_fd_t* fd_out);

/// <summary>
/// Reads the next directory entry.
/// </summary>
/// <param name="fd">Open directory descriptor.</param>
/// <param name="entry">Destination directory-entry record.</param>
/// <param name="end_out">Receives 1 at end-of-directory, otherwise 0. May be null.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_readdir(
    neox_fd_t fd,
    neox_dir_entry_t* entry,
    uint8_t* end_out);

/// <summary>
/// Closes an open directory descriptor.
/// </summary>
/// <param name="fd">Open directory descriptor.</param>
/// <returns>NEOX_STATUS_OK on success, otherwise a NEOX error code.</returns>
neox_status_t neox_closedir(neox_fd_t fd);

#endif /* NEOX_FS_H */
