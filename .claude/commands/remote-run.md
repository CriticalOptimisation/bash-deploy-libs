---
description: Guide for using the remote_run.sh library to execute local scripts on a remote host over SSH without writing files to the remote filesystem. Triggers when the task involves running a script remotely, sourcing files over SSH, deploying without SCP/rsync, or using rr_run/rr_init/rr_cleanup.
---

# Remote Run Library Skill

## When to Use

Use `remote_run.sh` when you need to execute a local Bash script on a remote
host **without copying any file to the remote filesystem**.  The script and
every library it `source`s are kept on the local machine; the remote side
receives file content on demand through a private protocol channel established
by SSH port-forwarding.

Typical situations:
- Deploy or configure a remote host from a local script that `source`s
  `handle_state.sh`, `command_guard.sh`, or other local libraries.
- Run a script that must not leave artefacts on the remote host.
- Test or validate remote state without a persistent SSH session per command.

Do **not** use `remote_run.sh` when:
- The script must write persistent files to the remote host (use `scp` or `rsync`).
- The remote host does not have Bash ≥ 4.3.
- OpenBSD `nc` is not available on the local host.

## Core Reference

`docs/libraries/remote_run.rst` is the canonical local reference.
`config/remote_run.sh` is the implementation.

## Dependencies

| Dependency     | Side   | Notes                                          |
|----------------|--------|------------------------------------------------|
| Bash ≥ 4.3     | Both   | `local -n` (nameref), auto-assigned FDs        |
| OpenSSH client | Local  | `ssh -T`, `-R`, ControlMaster (`-M`)           |
| OpenSSH server | Remote | `sshd` running and reachable                   |
| `nc`           | Local  | OpenBSD variant only (`nc -lU socket`)         |
| `base64`       | Remote | Standard on all major Linux distributions      |

All local dependencies are guarded by `cg_guard` at source time.

## Standard Pattern

```bash
source "$(dirname "$0")/config/remote_run.sh"

# 1. Initialise: establish ControlMaster, optionally whitelist extra dirs.
local state
rr_init -S state --allow /path/to/extra/lib/dir  host.example.com

# 2. Run the script on the remote host.
#    The script may source any file under its own directory or whitelisted dirs.
rr_run -S state  host.example.com  /path/to/local_script.sh  [args...]

# 3. Tear down the ControlMaster.
rr_cleanup -S state
```

## API Summary

### `rr_init [-S <state>] [--allow <dir>] <host>`
Establishes a ControlMaster SSH connection.  Whitelists the script's own
directory automatically; use `--allow` for additional source directories.
The `-S <state>` variable carries all connection metadata to `rr_run` and
`rr_cleanup`.  Returns `RR_ERR_SSH_CONNECT_FAILED` if the connection cannot
be established.

### `rr_run [-S <state>] [--allow <dir>] <host> <script> [args...]`
Executes `<script>` on `<host>`.  The remote bash receives the script via
SSH stdin; file content requested by `source` inside the script is served
on demand over the protocol channel.  Returns the remote script's exit code.

### `rr_cleanup [-S <state>]`
Tears down the ControlMaster, killing all port forwards and multiplexed
sessions.

### `rr_resolve [-S <state>] <file>`
On the local originating machine: returns `<file>` unchanged (no-op).
On a relay (inside a remotely-running script): sends a `RESOLVE` request
and returns `/dev/fd/N` pointing to a dedicated transfer channel.  Use this
when a script running remotely needs to resolve the physical path of a
library file it will `source`.

## How the Protocol Works

1. `rr_init` opens a ControlMaster connection (`ssh -MNf`).
2. `rr_run` starts a local `nc` listener on a Unix-domain socket and asks SSH
   to forward an auto-allocated remote TCP port to it.
3. The bootstrap shell fragment is piped to `ssh -T` stdin; the remote bash
   reads it, opens `/dev/tcp/localhost/<port>` as a bidirectional fd, then
   runs the target script.
4. Every `source` in the remote script triggers a `GET <path>` request over
   that fd.  The local serve loop reads the file and sends it back.
5. `rr_cleanup` sends `ssh -O exit` to tear down all forwarded ports and the
   ControlMaster socket.

## Error Codes

| Constant                      | Value | Meaning                                |
|-------------------------------|-------|----------------------------------------|
| `RR_ERR_MISSING_ARGUMENT`     | 8     | Missing mandatory positional argument  |
| `RR_ERR_UNKNOWN_ARGUMENT`     | 9     | Unrecognised option                    |
| `RR_ERR_PATH_RESOLUTION_FAILED` | 13  | `realpath -m` failed on `--allow` path |
| `RR_ERR_SCRIPT_NOT_FOUND`     | 14    | Script absent or unreadable            |
| `RR_ERR_SSH_CONNECT_FAILED`   | 15    | ControlMaster connection failed        |
| `RR_ERR_PORT_FORWARD_FAILED`  | 16    | SSH port forward failed                |
| `RR_ERR_FETCH_FAILED`         | 17    | Remote sent ERR for a GET request      |
| `RR_ERR_RESOLVE_FAILED`       | 18    | Non-RESOLVE_OK reply to RESOLVE        |
| `RR_ERR_DEPENDENCY_MISSING`   | 19    | Source-time guard / load failed        |

## Key Constraints

- The remote script and every file it `source`s must reside under whitelisted
  directories.  Paths outside the whitelist are rejected with an ERR response.
- Only `source` (`.`) triggers protocol fetches; `exec`, `bash -c`, and direct
  binary invocations are not intercepted.
- The library serialises `_rr_serve_loop` and `_rr_do_resolve` into the
  bootstrap so the remote bash can handle relay calls without any local file.
- `nc` must be the OpenBSD variant.  BSD/traditional `nc` variants that require
  `-p` for port specification are not supported.
- Use `cg_guard` for any external commands called inside a script that will be
  run via `rr_run`; PATH on the remote side may differ from local.
