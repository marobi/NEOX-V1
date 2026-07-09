# neosh, nbox, and Applets

## neosh

`neosh` is the interactive shell task. It owns shell policy:

- prompt generation
- receiving complete edited command lines
- prompt-prefix stripping
- command resolution
- parent/direct versus child/spawned execution policy
- future redirection and pipe setup
- child spawn/commit/wait orchestration

The RP VDU/console layer owns the screen and transparent line editing. `neosh` consumes the completed edited line delivered through stdin.

## nbox

`nbox` is the resident applet dispatcher/executor. It handles one command line or one applet launch. It must not own:

- prompts
- process allocation
- fd setup policy
- redirection
- pipes
- shell job policy

## Applets

Applets are individual command implementations. Command wrappers parse command-line arguments for direct dispatch. Spawned child applets use `nbox_child_entry`, which loads launch arguments first and then calls core applet routines directly.

## Shared applet scratch

Applet scratch storage is shared inside the resident user image. This is acceptable because one applet runs inside one process/context at a time. Kernel state must not rely on that assumption.
