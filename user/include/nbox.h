#ifndef NBOX_H
#define NBOX_H

#include <stdint.h>

#include <neox/types.h>

#define NBOX_LINE_MAX ((neox_size_t)64u)

#define NBOX_EXEC_PARENT  ((uint8_t)0u)
#define NBOX_EXEC_CHILD   ((uint8_t)1u)
#define NBOX_EXEC_NONE    ((uint8_t)0xFEu)
#define NBOX_EXEC_UNKNOWN ((uint8_t)0xFFu)

#define NBOX_APPLET_PWD   ((uint8_t)0x01u)
#define NBOX_APPLET_CD    ((uint8_t)0x02u)
#define NBOX_APPLET_LS    ((uint8_t)0x03u)
#define NBOX_APPLET_CAT   ((uint8_t)0x04u)
#define NBOX_APPLET_RM    ((uint8_t)0x05u)
#define NBOX_APPLET_MV    ((uint8_t)0x06u)
#define NBOX_APPLET_MKDIR ((uint8_t)0x07u)
#define NBOX_APPLET_RMDIR ((uint8_t)0x08u)
#define NBOX_APPLET_CP    ((uint8_t)0x09u)
#define NBOX_APPLET_PS    ((uint8_t)0x0Au)
#define NBOX_APPLET_ECHO  ((uint8_t)0x0Bu)
#define NBOX_APPLET_KILL  ((uint8_t)0x0Cu)
#define NBOX_APPLET_NONE  ((uint8_t)0xFFu)

extern char nbox_line_buf[64];
extern uint8_t nbox_line_len;
extern uint8_t nbox_exec_mode;
extern uint8_t nbox_launch_id;
extern uint8_t nbox_line_idx;

/// <summary>
/// Resolves the command stored in nbox_line_buf.
/// </summary>
/// <returns>Zero when resolved or empty; nonzero when unknown.</returns>
uint8_t neosh_nbox_resolve(void);

/// <summary>
/// Executes the currently resolved command in the current process.
/// </summary>
/// <returns>The applet status.</returns>
neox_status_t neosh_nbox_dispatch(void);

/// <summary>
/// Writes the standard unknown-command diagnostic to stderr.
/// </summary>
/// <returns>Always zero.</returns>
uint8_t neosh_nbox_print_unknown(void);

/// <summary>
/// Executes one resident applet selected by launch ID.
/// </summary>
/// <param name="launch_id">Resident applet launch selector.</param>
/// <returns>The applet status.</returns>
neox_status_t __fastcall__ nbox_execute_launch_id(uint8_t launch_id);

#endif /* NBOX_H */
