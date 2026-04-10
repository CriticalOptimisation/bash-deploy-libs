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

guard nc ssh base64 realpath

# ---------------------------------------------------------------------------
# DESIGN OVERVIEW
# ---------------------------------------------------------------------------
#
# Two independent SSH channels are used per rr_run call:
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
# The bootstrap is a shell fragment injected into the remote stdin before the
# user script runs.  It:
#
#   1. Allocates the protocol fd dynamically:
#        exec {_rr_fd}<>/dev/tcp/localhost/<forwarded_port>
#
#   2. Generates and evals the `source' override with $_rr_fd inscribed
#      literally via printf, so the override is immune to later changes to
#      shell variables:
#        eval "source() { _rr_outer_wrapper <LITERAL_FD> \"\$@\"; }"
#
#   3. Propagates shell flags from the rr_run call site:
#        set -<flags_from_caller>
#      PS4 is set to display real source paths via the wrapper-to-path map.
#      The remote script may change flags at any time thereafter, exactly as
#      it would when run locally.
#
#   4. Calls _rr_outer_wrapper <fd> <script> [args...] to run the user script.
#
# ---------------------------------------------------------------------------
# DOUBLE WRAPPER
# ---------------------------------------------------------------------------
#
# _rr_outer_wrapper <fd> <script_path> [args...]
#   1. Sends GET <script_path> on <fd>; reads the entire base64 response into
#      a local variable `_content'.  nc on the local side sees EOF and exits.
#   2. Calls _rr_inner_wrapper "$_content" "$@".
#   3. Captures the return code and performs cleanup (close per-file fds,
#      update bookkeeping) regardless of whether the inner wrapper returned
#      normally or via `return'.
#   Local variables of the outer wrapper are protected from eval in the inner
#   wrapper by Bash scope rules.  handle_state is not used on the remote side.
#
# _rr_inner_wrapper <content> [args...]
#   eval "$content" as a single block.  This handles multi-line constructs
#   (function bodies, if/fi, while/done) and reproduces the parse-then-execute
#   semantics of `source'.  A `return' inside the content exits the inner
#   wrapper; the outer wrapper then runs cleanup.
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
# PROTOCOL MESSAGES
# ---------------------------------------------------------------------------
#
# All messages are single-line, newline-terminated, sent over the protocol fd.
#
#   Local → Remote (responses):
#     OK <base64_content>   file content, base64-encoded, single line
#     ERR <reason>          request denied or file not found
#     RESOLVE_OK <port>     dedicated nc port is ready (response to RESOLVE)
#
#   Remote → Local (requests):
#     GET <path>            fetch file content
#     RESOLVE <path>        open a dedicated nc for this file and return its port
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
#   opens a second SSH -R tunnel to B for that port.  A sends RESOLVE_OK
#   only after the tunnel is active (synchronised via ControlMaster -O forward,
#   which is synchronous).  B allocates a new fd dynamically (exec {fd}<>)
#   pointing at the new port, and returns /dev/fd/$fd.
#   The dedicated nc exits naturally at EOF; no file is written to B.
#
# Recursive relay (A → B → C):
#   B's rr_resolve triggers RESOLVE toward A; A opens a tunnel through B to C.
#   Each level uses its own dynamically allocated fds; no name collisions occur.
#
# Usage in a relay script running on B:
#   source config/remote_run.sh   # fetched from A via the implicit source override
#   rr_run "root@C" "$(rr_resolve deploy.sh)" --env production

# ---------------------------------------------------------------------------
# LOCAL API
# ---------------------------------------------------------------------------

# rr_init [-s <state>] [-S <var>] [--allow <path>] [--ssh-opt <opt>]
#
# Optional.  Captures default SSH options and whitelist entries into a
# handle_state vector.  Both -s (append) and -S (write) are supported.
# Omitting rr_init is valid; rr_run uses built-in defaults.
rr_init() {
    # TODO: implement
    :
}

# rr_run [-s <state>] [-S <var>] [--allow <path>] [--ssh-opt <opt>] [--] \
#        <user@host> <script.sh|/dev/fd/N> [args...]
#
# Executes <script.sh> on <user@host> via SSH.  All `source' calls inside the
# script resolve against the local filesystem via the protocol channel.
# Each call allocates its own fd and nc instance; parallel calls to different
# hosts are supported.
rr_run() {
    # TODO: implement
    :
}

# rr_resolve [-s <state>] <file>
#
# Returns a path from which <file> can be read.
# On the originating machine: returns <file> unchanged (no-op).
# On a relay machine: negotiates a dedicated nc tunnel via the RESOLVE
# protocol message and returns /dev/fd/N pointing at that tunnel.
rr_resolve() {
    # TODO: implement — detect whether running as relay by checking for the
    # protocol fd variable baked by the bootstrap; if absent, echo "$1".
    echo "$1"
}

# rr_cleanup [-s <state>] [-S <var>]
#
# No-op in the current implementation.  Reserved for a future ControlMaster
# mode that would hold a persistent multiplexed SSH connection across multiple
# rr_run calls.
rr_cleanup() {
    :
}

# ---------------------------------------------------------------------------
# REMOTE BOOTSTRAP (injected into remote stdin by rr_run)
# ---------------------------------------------------------------------------
#
# The bootstrap fragment is generated by rr_run as a here-document with the
# protocol fd port number and caller shell flags substituted at generation
# time.  It is never stored in a file.
#
# Stub: _rr_bootstrap_fragment <forwarded_port> <shell_flags> <script> [args...]
#   Prints the bootstrap fragment to stdout.
_rr_bootstrap_fragment() {
    # TODO: implement
    :
}

# ---------------------------------------------------------------------------
# REMOTE WRAPPERS  (defined on the remote side by the bootstrap)
# The stubs below document their signatures; they are never called locally.
# ---------------------------------------------------------------------------

# _rr_outer_wrapper <fd> <script_path> [args...]
#   Reads the entire file over <fd>, waits for nc EOF, then calls
#   _rr_inner_wrapper.  Performs cleanup on return regardless of how the
#   inner wrapper exits (normal, return).  Local variables here are shielded
#   from the inner eval by Bash scope rules.
_rr_outer_wrapper() {
    # TODO: implement (remote side — generated into bootstrap fragment)
    :
}

# _rr_inner_wrapper <content> [args...]
#   eval "$content" as a single block so that multi-line constructs parse
#   correctly and `return' exits only this function (caught by outer wrapper).
_rr_inner_wrapper() {
    # TODO: implement (remote side — generated into bootstrap fragment)
    :
}
