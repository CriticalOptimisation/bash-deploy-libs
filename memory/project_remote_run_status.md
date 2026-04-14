---
name: remote_run implementation — current SCM status
description: Progress on issue #58 (remote_run library); which SCM task is next and what was approved
type: project
---

GitHub issue: CriticalOptimisation/bash-deploy-libs#58
Branch: `feature/issue-58-remote-run`
Last commit: 990d899

## Completed tasks

- Task 2 (Issue Assessment): approved by lepeuvedic — "OK for a first attempt"
- Task 3 (Implementation Planning): approved implicitly; amendments for auto-FD assignment, nc+SSH-R architecture, PTY/signal handling all accepted
- Task 4 (Docs + Preliminary Tests): approved by lepeuvedic — user said "I will now check your preparation work"

## Next task

**Task 5 — Implementation** (`config/remote_run.sh`)

Awaiting reviewer sign-off on Task 4 before starting. The reviewer said they will check the preparation work — check issue #58 comments at the start of the next session to confirm approval.

## Approved architecture (final)

- **Protocol channel**: local `nc -l -p $LOCAL_PORT` ← SSH `-R $REMOTE_PORT:localhost:$LOCAL_PORT` ← remote `bash /dev/fd/3 3<>/dev/tcp/localhost/$REMOTE_PORT`
- **Interactive terminal**: `ssh -tt` (PTY); remote bootstrap does `exec 0</dev/tty 1>/dev/tty 2>/dev/tty` when `/dev/tty` exists
- **Auto-assigned FDs**: `exec {__rr_proto_fd}<>&3` (Bash 4.1+, covered by 4.3 requirement)
- **source override**: `printf 'GET %s\n' "$path" >&"$__rr_proto_fd"` → `IFS= read -r resp <&"$__rr_proto_fd"` → base64 decode → wrap in `__rr_wN()` → call with args
- **FUNCNAME masking**: `unset 'FUNCNAME[0]'` inside wrapper (not `[-1]`) — to be verified and documented
- **PTY/signal**: `_rr_is_foreground_tty` decides `-tt` vs `-T`; terminal restore trap; bootstrap guards `exec 0</dev/tty` with `[[ -e /dev/tty ]]`
- **nc check**: `command -v nc` at startup; error message if missing
- **`--ssh-opt`**: accumulates extra SSH flags (needed for tests with non-default port/key)

## Files to create/modify in Task 5

- `config/remote_run.sh` — **create** (main library)
- `test/test-remote_run.bats` — **extend** with edge-case tests after implementation

## Key implementation details to remember

- Bootstrap is the FIRST bytes sent over the nc socket (program feed), then the loop switches to serving GET requests
- Remote bash invoked as: `bash --noprofile --norc /dev/fd/3 3<>/dev/tcp/localhost/$REMOTE_PORT`
- SSH: `ssh -tt -o ExitOnForwardFailure=yes -R "$REMOTE_PORT:localhost:$LOCAL_PORT" "${SSH_OPTS[@]}" "$host" "bash ..."`
- `_rr_is_foreground_tty`: returns 0 if `[[ -t 0 ]]` AND `stty` succeeds (proves we're fg)
- Terminal restore trap: `saved=$(stty -g 2>/dev/null); trap "stty '$saved' 2>/dev/null" EXIT INT TERM HUP`
- Wrapper naming: `__rr_w${N}` where N is a counter; map `__rr_source_map[$N]="$path"` for diagnostics
- Line offset: wrapper header is exactly 1 line (`__rr_wN() {`), so BASH_LINENO is off by 1

**Why:** All architecture decisions were driven by reviewer discussion on issue #58 to avoid stdout/PTY conflicts, support interactive commands, and work without a local SSH server.

**How to apply:** Read this before starting Task 5. Check issue #58 for any new reviewer comments that might amend the plan.
