#!/bin/bash
# File: config/remote_run.sh
# Description: Execute local shell scripts on remote hosts via SSH without
#              writing any file to the remote filesystem.  The main script and
#              every library it sources are served on demand from the local
#              machine through a private TCP channel established by SSH -R.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__REMOTE_RUN_SH_INCLUDED:-} ]] && __REMOTE_RUN_SH_INCLUDED=1 || return 0

# shellcheck source=config/command_guard.sh
# shellcheck disable=SC1091
source "${BASH_SOURCE%/*}/command_guard.sh"

# shellcheck source=config/handle_state.sh
# shellcheck disable=SC1091
source "${BASH_SOURCE%/*}/handle_state.sh"
# handle_state.sh auto-starts the FIFO reader on source; terminate it
# immediately so rr_init owns the start/stop lifecycle cleanly.
hs_cleanup_output

guard nc ssh base64 realpath mktemp dirname cat sleep

# ---------------------------------------------------------------------------
# DESIGN OVERVIEW — per rr_run invocation
# ---------------------------------------------------------------------------
#
# Step 1 — ControlMaster connection
#   ssh -MNf -S _ctl_sock -o ControlPersist=yes [user-opts] host
#   Establishes one TCP connection.  ssh -f backgrounds after authentication,
#   so _ctl_sock is immediately usable when the command returns.  All further
#   SSH traffic for this rr_run call is multiplexed over this single connection.
#
# Step 2 — Remote port allocation (synchronous, clean stdout)
#   _port=$(ssh -S _ctl_sock -O forward -R 127.0.0.1:0:_local_sock host)
#   sshd binds a free TCP port on the remote 127.0.0.1 and forwards connections
#   to _local_sock (a local Unix-domain socket where nc listens).  The port
#   number is returned as stdout by ssh -O forward — no stderr grep required.
#
# Step 3 — Bootstrap delivery and execution
#   The bootstrap (shell fragment with _port baked in) is written to a local
#   FIFO; the FIFO kernel buffer holds it until the remote bash drains it.
#   ssh -T -S _ctl_sock host "bash --norc --noprofile" < _boot_fifo
#   The remote bash opens /dev/tcp/127.0.0.1/_port as a bidirectional fd,
#   installs source() and rr_resolve() overrides with the fd number baked in,
#   and runs the user script.  No file is written to the remote filesystem.
#
# Step 4 — Teardown
#   ssh -S _ctl_sock -O exit host
#   Closes the ControlMaster (and with it all port forwards and sessions).
#
# ---------------------------------------------------------------------------
# rr_resolve — using the ControlMaster for additional port forwards
# ---------------------------------------------------------------------------
#
# When a relay machine B needs to resolve a file back to A, the serve loop
# on A receives a RESOLVE request.  A then:
#   new_sock=$(mktemp -u) && nc -lU new_sock &
#   new_port=$(ssh -S _ctl_sock -O forward -R 127.0.0.1:0:new_sock host_B)
#   send RESOLVE_OK new_port on the protocol fd
# B opens exec {fd}<>/dev/tcp/127.0.0.1/new_port and returns /dev/fd/$fd.
# Each RESOLVE reuses the existing ControlMaster — no new TCP handshake.
#
# ---------------------------------------------------------------------------
# REMOTE BOOTSTRAP SEQUENCE
# ---------------------------------------------------------------------------
#
# The bootstrap is a shell fragment written to a local FIFO connected to the
# remote bash's stdin.  The port is known before the bash session starts, so
# the FIFO is written and closed before ssh runs the bash command.  The
# bootstrap:
#
#   1. Opens the protocol channel via a single bidirectional fd:
#        exec {_rr_proto_fd}<>/dev/tcp/127.0.0.1/<N>
#      where N is the remote TCP port returned by ssh -O forward.
#
#   2. Generates and evals the `source' override and `rr_resolve' with the
#      fd value inscribed literally, so both are immune to later changes:
#        eval "$(printf 'source() { _rr_outer_wrapper %d "$@"; }' "$_rr_proto_fd")"
#        eval "$(printf 'rr_resolve() { _rr_do_resolve %d "$@"; }' "$_rr_proto_fd")"
#
#   3. Propagates shell flags from the rr_run call site:
#        set -<flags_from_caller>
#      PS4 is set to display source paths when tracing is active.
#      The remote script may change flags at any time thereafter.
#
#   4. Defines _rr_outer_wrapper, _rr_inner_wrapper, _rr_do_resolve
#      (serialised from this file via declare -f).
#
#   5. Calls _rr_outer_wrapper <fd> <script> [args...] to run the user script.
#
# ---------------------------------------------------------------------------
# DOUBLE WRAPPER
# ---------------------------------------------------------------------------
#
# _rr_outer_wrapper <fd> <script_path> [args...]
#   1. Sends GET <script_path> on <fd>; reads the entire base64 response into
#      a local variable.  nc on the local side sees EOF for that request and
#      moves to the next.
#   2. Calls _rr_inner_wrapper "$_content" "$@".
#   3. Captures the return code; local variables here are shielded from the
#      inner eval by Bash scope rules.
#
# _rr_inner_wrapper <content> [args...]
#   eval "$content" as a single block.  This handles multi-line constructs
#   (function bodies, if/fi, while/done) and reproduces the parse-then-execute
#   semantics of `source'.  A `return' inside the content exits the inner
#   wrapper; the outer wrapper continues normally.
#   Note: `exit' destroys the entire shell stack; the outer wrapper cannot
#   intercept it (documented limitation).
#
# ---------------------------------------------------------------------------
# FILE DESCRIPTOR ALLOCATION RULE (project-wide)
# ---------------------------------------------------------------------------
#
# This library allocates all file descriptors dynamically (exec {var}<>).
# It cannot protect itself against application code that opens hard-coded fd
# numbers after this library is sourced.  Applications must either:
#   - use dynamic allocation themselves, OR
#   - open all hard-coded fds BEFORE sourcing any library in this project.
#
# ---------------------------------------------------------------------------
# REMOTE SCRIPT CATEGORIES
# ---------------------------------------------------------------------------
#
# Category 1 — remote-run-aware scripts
#   The script sources config/remote_run.sh and uses the rr_* API explicitly.
#   It may call rr_run itself for nested remote execution (relay scenario).
#   The bootstrap defines no rr_init/rr_run of its own; sourcing remote_run.sh
#   on the remote redefines the full API cleanly without collision.
#
# Category 2 — unaware scripts
#   The script has no knowledge of remote_run.  It uses `source' normally;
#   the implicit override intercepts all such calls transparently.
#
# ---------------------------------------------------------------------------
# PROTOCOL MESSAGES (single-line, newline-terminated, over the protocol fd)
# ---------------------------------------------------------------------------
#
#   Remote → Local (requests):
#     GET <path>            fetch file content
#     RESOLVE <path>        open a dedicated nc for this file and return its port
#
#   Local → Remote (responses):
#     OK <base64_content>   file content, base64-encoded, no padding newline
#     ERR <reason>          request denied or file not found
#     RESOLVE_OK <port>     dedicated nc port is ready (response to RESOLVE)
#
# ---------------------------------------------------------------------------
# rr_resolve — RELAY FILE TRANSFER
# ---------------------------------------------------------------------------
#
# On the originating machine (A):
#   rr_resolve is a no-op; it returns the file path unchanged.
#
# NOTE — nested source() does NOT use rr_resolve:
#   _rr_outer_wrapper fetches each sourced file in a single round-trip on the
#   already-open protocol fd (GET request → base64 response).  No additional
#   connection is needed for nested source calls, regardless of depth.
#   rr_resolve is ONLY needed for the relay scenario (A → B → C).
#
# On a relay machine (B, executing a script fetched from A):
#   rr_resolve sends RESOLVE <path> on the protocol fd back to A.
#   A allocates a new ephemeral local socket, starts a dedicated nc listener,
#   and adds a new -R tunnel from B to that socket.  Because opening a fresh
#   SSH connection for every resolved file is prohibitively slow, this tunnel
#   MUST be opened over an existing ControlMaster connection that rr_run
#   established when it first SSH'd into B (ssh -o ControlMaster=yes
#   -o ControlPath=<socket>).  The forward is added with `ssh -O forward',
#   which is synchronous: A signals RESOLVE_OK <port> only after sshd on B
#   has bound the port.  B opens exec {fd}<>/dev/tcp/localhost/<port> and
#   returns /dev/fd/$fd.  The dedicated nc exits at EOF; no file is written.
#
# Recursive relay (A → B → C):
#   B's rr_resolve triggers RESOLVE toward A; A opens a tunnel through B to C.
#   Each level uses its own dynamically allocated fds; no name collisions occur.

# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

# _rr_path_allowed <path> <whitelist_str>
# Returns 0 if <path> falls within any entry in the newline-delimited
# <whitelist_str>, 1 otherwise.  Both <path> and whitelist entries must be
# normalised absolute paths.
_rr_path_allowed() {
    local _path=$1 _wl=$2
    local _entry
    while IFS= read -r _entry; do
        [[ -z "$_entry" ]] && continue
        if [[ "$_path" == "$_entry" || "$_path" == "$_entry/"* ]]; then
            return 0
        fi
    done <<< "$_wl"
    return 1
}

# _rr_serve_loop <read_fd> <write_fd> <whitelist_str>
# Processes GET and RESOLVE requests from the remote side.
# Runs in a background subshell; exits when the remote closes the connection.
_rr_serve_loop() {
    local _rfd=$1 _wfd=$2 _wl=$3
    local _req _path _norm _b64

    while IFS= read -r _req <&"$_rfd"; do
        case "$_req" in
            GET\ *)
                _path="${_req#GET }"
                _norm=$(realpath -m "$_path" 2>/dev/null) || _norm=""
                if [[ -z "$_norm" ]] || ! _rr_path_allowed "$_norm" "$_wl"; then
                    printf 'ERR path not in whitelist: %s\n' "$_path" >&"$_wfd"
                elif [[ ! -r "$_norm" ]]; then
                    printf 'ERR file not readable: %s\n' "$_norm" >&"$_wfd"
                else
                    _b64=$(base64 -w0 < "$_norm")
                    printf 'OK %s\n' "$_b64" >&"$_wfd"
                fi
                ;;
            RESOLVE\ *)
                # TODO (issue #58): implement RESOLVE protocol for relay support.
                printf 'ERR RESOLVE not yet implemented\n' >&"$_wfd"
                ;;
            "")
                break
                ;;
        esac
    done
}

# _rr_serve_loop_fifo <read_fifo> <write_fifo> <whitelist_str>
# Same as _rr_serve_loop but takes FIFO paths instead of fd numbers.
# Used by rr_run to avoid coproc fd-inheritance races.
_rr_serve_loop_fifo() {
    local _rfifo=$1 _wfifo=$2 _wl=$3
    local _req _path _norm _b64

    # Open both ends of both FIFOs before entering the loop so that neither
    # open(2) blocks indefinitely waiting for the other side.
    exec {_rr_sl_rfd}<"$_rfifo" {_rr_sl_wfd}>"$_wfifo"

    while IFS= read -r _req <&"$_rr_sl_rfd"; do
        case "$_req" in
            GET\ *)
                _path="${_req#GET }"
                _norm=$(realpath -m "$_path" 2>/dev/null) || _norm=""
                if [[ -z "$_norm" ]] || ! _rr_path_allowed "$_norm" "$_wl"; then
                    printf 'ERR path not in whitelist: %s\n' "$_path" >&"$_rr_sl_wfd"
                elif [[ ! -r "$_norm" ]]; then
                    printf 'ERR file not readable: %s\n' "$_norm" >&"$_rr_sl_wfd"
                else
                    _b64=$(base64 -w0 < "$_norm")
                    printf 'OK %s\n' "$_b64" >&"$_rr_sl_wfd"
                fi
                ;;
            RESOLVE\ *)
                printf 'ERR RESOLVE not yet implemented\n' >&"$_rr_sl_wfd"
                ;;
            "")
                break
                ;;
        esac
    done
    exec {_rr_sl_rfd}>&- {_rr_sl_wfd}>&-
}

# ---------------------------------------------------------------------------
# REMOTE-SIDE FUNCTIONS
# These are defined here so declare -f can serialise them into the bootstrap.
# They are harmless if accidentally called locally (no protocol fd exists).
# ---------------------------------------------------------------------------

# _rr_outer_wrapper <fd> <path> [args...]
# Fetches <path> over the bidirectional <fd> via GET, then calls
# _rr_inner_wrapper with the decoded content and any extra args.
_rr_outer_wrapper() {
    local _rr_ow_fd=$1 _rr_ow_path=$2
    shift 2

    # Request file
    printf 'GET %s\n' "$_rr_ow_path" >&"$_rr_ow_fd"

    # Read response
    local _rr_ow_resp
    IFS= read -r _rr_ow_resp <&"$_rr_ow_fd"
    local _rr_ow_status="${_rr_ow_resp%% *}"
    local _rr_ow_b64="${_rr_ow_resp#* }"

    if [[ "$_rr_ow_status" != "OK" ]]; then
        printf '[rr] ERROR fetching %s: %s\n' "$_rr_ow_path" "$_rr_ow_b64" >&2
        return 1
    fi

    # Decode
    local _rr_ow_content
    _rr_ow_content=$(printf '%s' "$_rr_ow_b64" | base64 -d)

    # Execute via inner wrapper; $@ are the args passed to source
    _rr_inner_wrapper "$_rr_ow_content" "$@"
}

# _rr_inner_wrapper <content> [args...]
# eval's <content> as a single block so that multi-line constructs parse
# correctly and `return' exits only this function.
_rr_inner_wrapper() {
    local _rr_iw_content=$1
    shift
    # $@ is now the args passed to `source <file> [args...]'
    eval "$_rr_iw_content"
}

# _rr_do_resolve <fd> <file>
# Remote-side implementation of rr_resolve.  Sends a RESOLVE request on <fd>
# and reads the response from <fd>, returning /dev/fd/N for the dedicated
# transfer channel.  On the originating machine this function is never called
# (rr_resolve is a no-op there); it is only injected into the bootstrap for
# relay machines.
_rr_do_resolve() {
    local _rr_dr_fd=$1 _rr_dr_file=$2

    printf 'RESOLVE %s\n' "$_rr_dr_file" >&"$_rr_dr_fd"

    local _rr_dr_resp
    IFS= read -r _rr_dr_resp <&"$_rr_dr_fd"
    local _rr_dr_status="${_rr_dr_resp%% *}"
    local _rr_dr_port="${_rr_dr_resp#* }"

    if [[ "$_rr_dr_status" != "RESOLVE_OK" ]]; then
        printf '[rr] ERROR resolving %s: %s\n' "$_rr_dr_file" "$_rr_dr_port" >&2
        return 1
    fi

    local _rr_dr_newfd
    exec {_rr_dr_newfd}<>/dev/tcp/127.0.0.1/"$_rr_dr_port"
    printf '/dev/fd/%d' "$_rr_dr_newfd"
}

# ---------------------------------------------------------------------------
# BOOTSTRAP FRAGMENT GENERATOR
# ---------------------------------------------------------------------------

# _rr_bootstrap_fragment <port> <flags> <pipefail> <script> [args...]
# Prints the bootstrap shell fragment that the remote bash reads from stdin.
# <port> is the TCP port sshd allocated on the remote loopback via -R 0:sock.
# The bootstrap opens /dev/tcp/localhost/<port> as a single bidirectional fd,
# wires up source() and rr_resolve() with the fd number baked in, propagates
# caller shell flags, and runs the user script.
_rr_bootstrap_fragment() {
    local _port=$1 _flags=$2 _pipefail=$3 _script=$4
    shift 4

    # Serialise remote functions from this process
    local _outer_def _inner_def _resolve_def
    _outer_def=$(declare -f _rr_outer_wrapper)
    _inner_def=$(declare -f _rr_inner_wrapper)
    _resolve_def=$(declare -f _rr_do_resolve)

    # Shell options to restore
    local _set_cmds=""
    [[ -n "${_flags//[[:space:]]/}" ]] && _set_cmds+="set -${_flags}"$'\n'
    [[ "$_pipefail" == 1 ]] && _set_cmds+="set -o pipefail"$'\n'

    # Quoted script path and args for safe inclusion
    local _qs _qa=""
    _qs=$(printf '%q' "$_script")
    local _a
    for _a in "$@"; do _qa+=" $(printf '%q' "$_a")"; done

    cat <<BOOTSTRAP
exec {_rr_proto_fd}<>/dev/tcp/127.0.0.1/${_port} || { printf '[rr] ERROR: cannot connect to protocol channel\n' >&2; exit 1; }
eval "\$(printf 'source() { _rr_outer_wrapper %d "\$@"; }' "\$_rr_proto_fd")"
eval "\$(printf 'rr_resolve() { _rr_do_resolve %d "\$@"; }' "\$_rr_proto_fd")"
${_set_cmds}PS4='[rr:\${BASH_SOURCE[0]:-?}:\$LINENO]+ '
$_outer_def
$_inner_def
$_resolve_def
_rr_outer_wrapper "\$_rr_proto_fd" $_qs$_qa
BOOTSTRAP
}

# ---------------------------------------------------------------------------
# PUBLIC LOCAL API
# ---------------------------------------------------------------------------

# rr_init [-s <state>] [-S <var>] [--allow <path>] [--ssh-opt <opt>]
#
# Optional.  Appends rr_init's own state (_rr_ssh_opts_str, _rr_whitelist_str)
# to a shared application state vector managed by hs_persist_state.  Each
# library in a project appends its own variables to the same shared state;
# hs_persist_state's collision detection prevents initialising the same library
# twice on the same state variable (intentional error).
#
# -s <state>  Load a state string produced by previous library calls.  eval in
#             rr_init only touches rr's own local vars (hs_persist_state emits
#             `if local -p var` guards, so other libraries' variables are
#             silently skipped).  Used to carry state from other libraries.
# -S <var>    Read-modify-write: read the current value of <var> as the input
#             state (if -s is not also given), append rr_init's vars, and write
#             the combined result back.  Do NOT pass the same <var> to both -s
#             and -S: that would make rr_init's own vars appear twice → collision.
#
# Correct multi-library accumulation pattern:
#   other_lib_init -S st [opts]   # st: other_lib's vars
#   rr_init        -S st [opts]   # st: other_lib's vars + rr's vars (reads st first)
#   rr_run         -s "$st" user@host script.sh
rr_init() {
    hs_setup_output_to_stdout  # start FIFO reader; paired with rr_cleanup's hs_cleanup_output
    local _rr_ssh_opts_str="" _rr_whitelist_str=""
    local _out_var="" _in_state=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) shift; _in_state=$1; shift ;;
            -S) shift; _out_var=$1; shift ;;
            --ssh-opt) shift
                _rr_ssh_opts_str+="${_rr_ssh_opts_str:+$'\n'}$1"
                shift ;;
            --allow) shift
                local _p
                _p=$(realpath -m "$1") || { echo "[ERROR] rr_init: cannot resolve path '$1'" >&2; return 1; }
                _rr_whitelist_str+="${_rr_whitelist_str:+$'\n'}$_p"
                shift ;;
            --) shift; break ;;
            *) echo "[ERROR] rr_init: unknown option '$1'" >&2; return 1 ;;
        esac
    done

    # hs_persist_state -S <var> already reads the current value of <var> as the
    # existing state for collision detection, appends our vars, and writes back —
    # that is the correct read-modify-write path.  We never eval state here:
    # either the state is empty (no-op) or it already contains our vars
    # (collision → intentional double-init error from hs_persist_state).
    if [[ -n "$_out_var" ]]; then
        hs_persist_state -S "$_out_var" _rr_ssh_opts_str _rr_whitelist_str || return $?
    else
        hs_persist_state -s "$_in_state" _rr_ssh_opts_str _rr_whitelist_str
    fi
}

# rr_run [-s <state>] [-S <var>] [--allow <path>] [--ssh-opt <opt>] [--] \
#        <user@host> <script.sh|/dev/fd/N> [args...]
#
# Executes <script.sh> on <user@host> via SSH.  All `source' calls inside the
# script resolve against the local filesystem via the protocol channel.
# Each call allocates its own fd and nc instance; parallel calls to different
# hosts are supported.
rr_run() {
    local _rr_ssh_opts_str="" _rr_whitelist_str=""
    local _out_var=""

    # Parse options (merge any incoming state with per-call overrides)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) shift
                eval "$1"
                shift ;;
            -S) shift; _out_var=$1; shift ;;
            --ssh-opt) shift
                _rr_ssh_opts_str+="${_rr_ssh_opts_str:+$'\n'}$1"
                shift ;;
            --allow) shift
                local _p
                _p=$(realpath -m "$1") || { echo "[ERROR] rr_run: cannot resolve '$1'" >&2; return 1; }
                _rr_whitelist_str+="${_rr_whitelist_str:+$'\n'}$_p"
                shift ;;
            --) shift; break ;;
            -*) echo "[ERROR] rr_run: unknown option '$1'" >&2; return 1 ;;
            *) break ;;
        esac
    done

    local _host=$1 _script=$2
    shift 2
    local -a _args=("$@")

    # Check hard dependencies at call time (guard provides full-path wrappers,
    # but nc may have been absent at source time on systems without it).
    if ! command -v nc &>/dev/null; then
        echo "[ERROR] rr_run: nc is required but not found. Install netcat (e.g. apt install netcat-openbsd)." >&2
        return 1
    fi

    # Validate mandatory arguments
    if [[ -z "$_host" ]]; then
        echo "[ERROR] rr_run: missing host argument" >&2; return 1
    fi
    if [[ -z "$_script" ]]; then
        echo "[ERROR] rr_run: missing script argument" >&2; return 1
    fi
    if [[ "$_script" != /dev/fd/* && ! -f "$_script" ]]; then
        echo "[ERROR] rr_run: script not found or not readable: $_script" >&2; return 1
    fi

    # Add script directory to whitelist (unless it's an fd path)
    if [[ "$_script" != /dev/fd/* ]]; then
        local _sdir
        _sdir=$(realpath -m "$(dirname "$_script")")
        _rr_whitelist_str+="${_rr_whitelist_str:+$'\n'}$_sdir"
    fi

    # Local Unix-domain socket for nc (no TCP port needed locally; avoids
    # TOCTOU races).  mktemp -u generates a unique name without creating a file.
    local _local_sock
    _local_sock=$(mktemp -u)

    # Capture shell flags to propagate (strip non-settable flags s, c, i)
    local _flags="${-//[sci]/}"
    local _pipefail=0; [[ -o pipefail ]] && _pipefail=1

    # Build SSH option array (word-split each --ssh-opt string)
    local -a _ssh_opts=()
    local _opt_line
    while IFS= read -r _opt_line; do
        [[ -z "$_opt_line" ]] && continue
        # shellcheck disable=SC2206
        local -a _words=($_opt_line)
        _ssh_opts+=("${_words[@]}")
    done <<< "$_rr_ssh_opts_str"

    # Protocol server: nc listens on a local Unix socket; the serve loop reads
    # requests from nc's stdout and writes responses to nc's stdin via two FIFOs.
    # FIFOs avoid coproc fd-inheritance races.  Both are opened O_RDWR so that
    # neither open(2) blocks waiting for the other side.
    local _fifo_in _fifo_out
    _fifo_in=$(mktemp -u) && mkfifo "$_fifo_in"
    _fifo_out=$(mktemp -u) && mkfifo "$_fifo_out"

    local _fd_in _fd_out
    exec {_fd_in}<>"$_fifo_in" {_fd_out}<>"$_fifo_out"

    nc -lU "$_local_sock" <&"$_fd_in" >&"$_fd_out" &
    local _nc_pid=$!

    _rr_serve_loop "$_fd_out" "$_fd_in" "$_rr_whitelist_str" &
    local _srv_pid=$!

    exec {_fd_in}>&- {_fd_out}>&-

    # Bootstrap FIFO: remote bash reads the bootstrap script from its stdin.
    # Open the write end O_RDWR so the open(2) does not block before SSH starts.
    local _boot_fifo
    _boot_fifo=$(mktemp -u) && mkfifo "$_boot_fifo"
    local _boot_wfd
    exec {_boot_wfd}<>"$_boot_fifo"

    # ControlMaster socket for this rr_run invocation.
    local _ctl_sock
    _ctl_sock=$(mktemp -u)

    # Step 1: Establish ControlMaster.
    # ssh -f goes to background after authentication succeeds, so _ctl_sock is
    # ready immediately on return.  All further SSH traffic is multiplexed here.
    # Auth-related client messages are suppressed (they go to stderr, not needed).
    if ! ssh -MNf \
            -S "$_ctl_sock" \
            -o ControlPersist=yes \
            "${_ssh_opts[@]}" "$_host" 2>/dev/null
    then
        echo "[ERROR] rr_run: ControlMaster connection to $_host failed" >&2
        exec {_boot_wfd}>&-
        kill "$_nc_pid" "$_srv_pid" 2>/dev/null
        wait "$_nc_pid" "$_srv_pid" 2>/dev/null
        rm -f "$_fifo_in" "$_fifo_out" "$_local_sock" "$_boot_fifo" "$_ctl_sock"
        return 1
    fi

    # Step 2: Allocate a remote TCP port for the protocol channel.
    # ssh -O forward prints the allocated port to stdout — no grep on stderr.
    # 127.0.0.1:0 requests any free port bound to the remote loopback only.
    local _port
    _port=$(ssh -S "$_ctl_sock" -O forward \
                -R "127.0.0.1:0:${_local_sock}" \
                "$_host" 2>/dev/null)
    if [[ $? -ne 0 || -z "$_port" ]]; then
        echo "[ERROR] rr_run: -O forward failed (AllowTcpForwarding enabled on remote sshd?)" >&2
        ssh -S "$_ctl_sock" -O exit "$_host" 2>/dev/null
        exec {_boot_wfd}>&-
        kill "$_nc_pid" "$_srv_pid" 2>/dev/null
        wait "$_nc_pid" "$_srv_pid" 2>/dev/null
        rm -f "$_fifo_in" "$_fifo_out" "$_local_sock" "$_boot_fifo" "$_ctl_sock"
        return 1
    fi

    # Step 3: Write bootstrap (port baked in) to FIFO, then close the write end.
    # The kernel FIFO buffer holds the data until the remote bash drains it.
    # Closing _boot_wfd delivers EOF to the remote bash after the bootstrap,
    # terminating bash's stdin cleanly once the user script has been fetched.
    _rr_bootstrap_fragment "$_port" "$_flags" "$_pipefail" \
        "$_script" "${_args[@]}" >&"$_boot_wfd"
    exec {_boot_wfd}>&-

    # Step 4: Run remote bash via the ControlMaster session (no new TCP handshake).
    # Remote stderr flows naturally back to our stderr through the mux.
    local _rc
    ssh -T -S "$_ctl_sock" "$_host" \
        "bash --norc --noprofile" \
        < "$_boot_fifo"
    _rc=$?

    # Step 5: Tear down the ControlMaster (closes all port forwards and sessions).
    ssh -S "$_ctl_sock" -O exit "$_host" 2>/dev/null

    kill "$_nc_pid" "$_srv_pid" 2>/dev/null
    wait "$_nc_pid" "$_srv_pid" 2>/dev/null
    rm -f "$_fifo_in" "$_fifo_out" "$_local_sock" "$_boot_fifo" "$_ctl_sock"

    return $_rc
}

# rr_resolve [-s <state>] <file>
#
# On the originating machine: returns <file> unchanged (no-op).
# On a relay machine (bootstrap has set _rr_proto_fd): sends a RESOLVE request
# and returns /dev/fd/N for the dedicated transfer channel.
rr_resolve() {
    # Consume optional -s state (ignored; rr_resolve needs no state here)
    if [[ "${1:-}" == "-s" ]]; then shift 2; fi

    local _file=$1

    # If _rr_proto_fd is not set we are on the originating machine
    if [[ -z "${_rr_proto_fd+x}" ]]; then
        printf '%s' "$_file"
        return 0
    fi

    # Relay machine: delegate to _rr_do_resolve with the baked fd.
    # Note: on the remote side this function is replaced by the baked version
    # generated in the bootstrap (eval of printf ... _rr_proto_fd).
    # This fallback handles the case where rr_resolve is called locally after
    # sourcing remote_run.sh on a machine that also happens to have _rr_proto_fd
    # set in its environment (unusual but possible).
    _rr_do_resolve "$_rr_proto_fd" "$_file"
}

# rr_cleanup [-s <state>] [-S <var>]
#
# Cleans up resources allocated by this library.  Must be called at the end of
# any script that sourced remote_run.sh, to terminate the handle_state logging
# FIFO reader started automatically when the library was sourced.  Omitting
# this call leaves the background reader running for up to 5 seconds (its idle
# timeout) before it self-terminates.
#
# When ControlMaster relay support is added (issue #58), rr_cleanup will also
# close the long-lived ControlMaster socket; the call site is already correct.
rr_cleanup() {
    local _in_state="" _out_var=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) shift; _in_state=$1; shift ;;
            -S) shift; _out_var=$1; shift ;;
            --) shift; break ;;
            *) echo "[ERROR] rr_cleanup: unknown option '$1'" >&2; return 1 ;;
        esac
    done

    # When -S is given without -s, read the current value of the -S variable as
    # the input state (read-modify-write semantics).
    if [[ -n "$_out_var" && -z "$_in_state" ]]; then
        _in_state="${!_out_var}"
    fi

    # Strip rr-managed variables from the shared state and write back to -S var.
    # State format (one block per variable, produced by hs_persist_state):
    #   if local -p VAR >/dev/null 2>&1; then\n  VAR=value\nfi\n
    # The outer fi has no indentation (col 0); the inner fi has 2 spaces, so
    # [[ "$_line" == "fi" ]] correctly identifies only the outer block terminator.
    if [[ -n "$_out_var" && -n "$_in_state" ]]; then
        local _stripped="" _skip=false _line
        while IFS= read -r _line || [[ -n "$_line" ]]; do
            if [[ "$_line" == "if local -p _rr_ssh_opts_str "* || \
                  "$_line" == "if local -p _rr_whitelist_str "* ]]; then
                _skip=true
            fi
            [[ "$_skip" == false ]] && _stripped+="${_line}"$'\n'
            [[ "$_skip" == true && "$_line" == "fi" ]] && _skip=false
        done <<< "$_in_state"
        printf -v "$_out_var" '%s' "$_stripped"
    fi

    hs_cleanup_output
}
