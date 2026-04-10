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

guard nc ssh base64 realpath

# ---------------------------------------------------------------------------
# DESIGN OVERVIEW
# ---------------------------------------------------------------------------
#
# Two SSH channels are established per rr_run call, plus one additional
# channel per concurrent rr_resolve call (closed at EOF of its transfer):
#
#   Protocol channel (TCP via SSH -R)
#     A nc listener starts on an ephemeral local port.  SSH forwards that
#     port on the remote to the local listener.  The remote shell opens the
#     forwarded port as a bidirectional fd allocated dynamically by Bash
#     (exec {fd}<>).  All file requests (GET, RESOLVE) and their responses
#     flow through this fd.
#
#   Interactive channel (PTY via SSH -tt / -T)
#     Standard SSH pseudo-terminal when the caller has a controlling terminal.
#     Falls back to -T (no PTY) in CI / cron contexts.
#
# ---------------------------------------------------------------------------
# REMOTE BOOTSTRAP SEQUENCE
# ---------------------------------------------------------------------------
#
# The bootstrap is a shell fragment injected as the SSH remote command (passed
# as a base64-encoded string to avoid stdin conflicts with the PTY).  It:
#
#   1. Allocates the protocol fd dynamically:
#        exec {_rr_proto_fd}<>/dev/tcp/localhost/<forwarded_port>
#
#   2. Generates and evals the `source' override and `rr_resolve' with the fd
#      value inscribed literally via printf, so both are immune to later
#      changes to shell variables:
#        eval "$(printf 'source() { _rr_outer_wrapper %d "$@"; }' "$_rr_proto_fd")"
#        eval "$(printf 'rr_resolve() { _rr_do_resolve %d "$@"; }' "$_rr_proto_fd")"
#
#   3. Redirects stdio to /dev/tty when a PTY is present (exec 0</dev/tty …).
#
#   4. Propagates shell flags from the rr_run call site:
#        set -<flags_from_caller>
#      PS4 is set to display source paths when tracing is active.
#      The remote script may change flags at any time thereafter.
#
#   5. Defines _rr_outer_wrapper, _rr_inner_wrapper, _rr_do_resolve
#      (serialised from this file via declare -f).
#
#   6. Calls _rr_outer_wrapper <fd> <script> [args...] to run the user script.
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
# On a relay machine (B, executing a script fetched from A):
#   rr_resolve sends RESOLVE <path> on the protocol fd back to A.
#   A allocates a new ephemeral port, starts a dedicated nc listener, and
#   opens a second SSH -R tunnel to B for that port.  A signals readiness
#   with RESOLVE_OK <port> only after the tunnel is active (synchronised via
#   ControlMaster -O forward, which is synchronous).  B allocates a new fd
#   dynamically (exec {fd}<>) pointing at the new port, and returns /dev/fd/$fd.
#   The dedicated nc exits naturally at EOF; no file is written to B.
#
# Recursive relay (A → B → C):
#   B's rr_resolve triggers RESOLVE toward A; A opens a tunnel through B to C.
#   Each level uses its own dynamically allocated fds; no name collisions occur.

# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

# _rr_free_port
# Prints an unused local TCP port number.  Tries python3, ruby, then probing.
_rr_free_port() {
    local _p
    _p=$(python3 -c \
        'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); \
         print(s.getsockname()[1]); s.close()' 2>/dev/null) \
        && printf '%s' "$_p" && return 0
    _p=$(ruby -rsocket \
        -e 's=TCPServer.new("127.0.0.1",0);puts s.addr[1];s.close' 2>/dev/null) \
        && printf '%s' "$_p" && return 0
    # Fallback: probe random high ports
    while IFS= read -r _p; do
        ! (: >/dev/tcp/127.0.0.1/"$_p") 2>/dev/null && { printf '%s' "$_p"; return 0; }
    done < <(awk 'BEGIN{srand();for(i=0;i<50;i++) printf "%d\n",int(rand()*16000)+49152}')
    return 1
}

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
# Fetches <path> over <fd> via GET, then calls _rr_inner_wrapper with the
# decoded content and any extra args.
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
# and returns /dev/fd/N for the dedicated transfer channel.
# On the originating machine this function is never called (rr_resolve is a
# no-op there); it is only injected into the bootstrap for relay machines.
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
    exec {_rr_dr_newfd}<>/dev/tcp/localhost/"$_rr_dr_port"
    printf '/dev/fd/%d' "$_rr_dr_newfd"
}

# ---------------------------------------------------------------------------
# BOOTSTRAP FRAGMENT GENERATOR
# ---------------------------------------------------------------------------

# _rr_bootstrap_fragment <port> <flags> <pipefail> <script> [args...]
# Prints the bootstrap shell fragment to stdout.  The caller base64-encodes
# it and passes it as the SSH remote command.
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
exec {_rr_proto_fd}<>/dev/tcp/localhost/$_port || { echo '[rr] ERROR: cannot connect to protocol channel' >&2; exit 1; }
eval "\$(printf 'source() { _rr_outer_wrapper %d "\$@"; }' "\$_rr_proto_fd")"
eval "\$(printf 'rr_resolve() { _rr_do_resolve %d "\$@"; }' "\$_rr_proto_fd")"
{ exec 0</dev/tty 1>/dev/tty 2>/dev/tty; } 2>/dev/null || true
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
# Optional.  Captures default SSH options and whitelist entries into a
# handle_state vector.  Both -s (consume existing state) and -S (write output
# state into a named variable) are supported.  Calling rr_run without a prior
# rr_init is valid; built-in defaults are used.
rr_init() {
    local _rr_ssh_opts_str="" _rr_whitelist_str=""
    local _out_var="" _in_state=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) shift
                _in_state=$1
                # Restore prior state into our locals
                local _rr_ssh_opts_str _rr_whitelist_str
                eval "$_in_state"
                shift ;;
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

    if [[ -n "$_out_var" ]]; then
        hs_persist_state -S "$_out_var" _rr_ssh_opts_str _rr_whitelist_str
    else
        hs_persist_state _rr_ssh_opts_str _rr_whitelist_str
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
    local _out_var="" _saved_stty=""

    # Parse options (merge any incoming state with per-call overrides)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) shift
                local _rr_ssh_opts_str _rr_whitelist_str
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

    # Find a free local port for the protocol channel
    local _port
    _port=$(_rr_free_port) || {
        echo "[ERROR] rr_run: cannot find a free local port" >&2; return 1
    }

    # Detect PTY availability
    local _tty_opt="-T"
    if [[ -t 0 ]]; then
        _tty_opt="-tt"
        _saved_stty=$(stty -g 2>/dev/null) || _saved_stty=""
        if [[ -n "$_saved_stty" ]]; then
            # Build trap string with $_saved_stty expanded now (intentional).
            local _stty_trap
            printf -v _stty_trap "stty '%s' 2>/dev/null; trap - INT TERM HUP EXIT" \
                "$_saved_stty"
            # shellcheck disable=SC2064  # expansion is intentional: $_saved_stty captured above
            trap "$_stty_trap" INT TERM HUP EXIT
        fi
    fi

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

    # Start the protocol server: nc listens on $_port; the serve loop reads
    # from nc's stdout and writes to nc's stdin via two FIFOs.  Using FIFOs
    # avoids coproc fd-inheritance races and works reliably across Bash versions.
    #
    # SSH -R forwards remote:$_port → local:$_port (127.0.0.1 not localhost, to
    # avoid resolution issues in some sshd configurations).
    local _fifo_in _fifo_out
    _fifo_in=$(mktemp -u) && mkfifo "$_fifo_in"
    _fifo_out=$(mktemp -u) && mkfifo "$_fifo_out"

    # Open both FIFOs in read-write mode to avoid open(2) blocking on the
    # named pipe until the other end is connected.
    local _fd_in _fd_out
    exec {_fd_in}<>"$_fifo_in" {_fd_out}<>"$_fifo_out"

    # nc reads from _fifo_in (responses we write) and writes to _fifo_out.
    # OpenBSD nc: nc -l <port>  (no -p flag for listen port)
    nc -l "$_port" <&"$_fd_in" >&"$_fd_out" &
    local _nc_pid=$!

    # Protocol server reads from _fifo_out (remote requests) and writes
    # responses to _fifo_in; runs in background, exits when nc exits.
    _rr_serve_loop "$_fd_out" "$_fd_in" "$_rr_whitelist_str" &
    local _srv_pid=$!

    # Close the fds in the parent; only nc and _rr_serve_loop need them.
    exec {_fd_in}>&- {_fd_out}>&-

    # Generate bootstrap and base64-encode it for safe injection as SSH command
    local _b64
    _b64=$(_rr_bootstrap_fragment "$_port" "$_flags" "$_pipefail" \
           "$_script" "${_args[@]}" | base64 -w0)

    # Execute on remote; bootstrap is decoded and evaluated by the remote shell.
    # Use 127.0.0.1 in -R to avoid 'localhost' ambiguity in sshd GatewayPorts.
    local _rc
    ssh "$_tty_opt" -R "127.0.0.1:${_port}:127.0.0.1:${_port}" \
        "${_ssh_opts[@]}" "$_host" \
        "printf '%s' '$_b64' | base64 -d | bash --norc --noprofile"
    _rc=$?

    # Cleanup
    kill "$_nc_pid" "$_srv_pid" 2>/dev/null
    wait "$_nc_pid" "$_srv_pid" 2>/dev/null
    rm -f "$_fifo_in" "$_fifo_out"
    if [[ -n "$_saved_stty" ]]; then
        stty "$_saved_stty" 2>/dev/null
        trap - INT TERM HUP EXIT
    fi

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
# No-op in the current implementation.  Reserved for a future ControlMaster
# mode that would hold a persistent multiplexed SSH connection across multiple
# rr_run calls.
rr_cleanup() {
    :
}
