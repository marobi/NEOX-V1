#ifndef NEOX_STATUS_H
#define NEOX_STATUS_H

#include <neox/types.h>

#define NEOX_STATUS_OK     ((neox_status_t)0u)
#define NEOX_STATUS_ENOENT ((neox_status_t)2u)
#define NEOX_STATUS_EIO    ((neox_status_t)3u)
#define NEOX_STATUS_EINTR  ((neox_status_t)4u)
#define NEOX_STATUS_EINVAL ((neox_status_t)6u)
#define NEOX_STATUS_EBADF  ((neox_status_t)9u)

#endif /* NEOX_STATUS_H */
