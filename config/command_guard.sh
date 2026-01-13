#!/bin/bash
# File: config/command_guard.sh
# Description: Guard external commands by shadowing them with full-path wrappers.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__COMMAND_GUARD_SH_INCLUDED:-} ]] && __COMMAND_GUARD_SH_INCLUDED=1 || return 0

# --- Public error codes --------------------------------------------------------
readonly CG_ERR_MISSING_COMMAND=1
readonly CG_ERR_INVALID_NAME=2
readonly CG_ERR_NOT_FOUND=3

# --- Internal helpers ---------------------------------------------------------
# Function:
#   _cg_resolve_command_path
# Description:
#   Resolve the full path of a command using a restricted PATH in a subshell.
# Usage:
#   _cg_resolve_command_path "ls"
_cg_resolve_command_path() {
    local cmd="$1"
    local resolved

    resolved="$(PATH='/usr/bin:/bin' command -v -- "$cmd")" || return 1
    if [ -z "$resolved" ] || [ "${resolved#/}" = "$resolved" ] || [ ! -x "$resolved" ]; then
        return 1
    fi

    printf '%s' "$resolved"
}

# --- Public API ---------------------------------------------------------------
# Function:
#   guard
# Description:
#   Defines a function named <command> that shadows the external command and
#   dispatches to it by full path with all arguments forwarded.
# Usage:
#   guard <command>
# Example:
#   guard ls
#   ls -l
#   # runs /usr/bin/ls -l (or /bin/ls)
# Errors:
#   CG_ERR_MISSING_COMMAND, CG_ERR_INVALID_NAME, CG_ERR_NOT_FOUND
# Notes:
#   Uses a restricted PATH ("/usr/bin:/bin") in a subshell to resolve the command.
#   This avoids resolving through user-controlled PATH entries.
#
#   This function uses eval to define the shadowing function; input is validated
#   to be a legal Bash identifier before eval is invoked.
guard() {
    local cmd="$1"
    local full_path

    if [ -z "$cmd" ]; then
        echo "[ERROR] guard: missing command name." >&2
        return "$CG_ERR_MISSING_COMMAND"
    fi

    if ! [[ "$cmd" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "[ERROR] guard: invalid command name '$cmd'." >&2
        return "$CG_ERR_INVALID_NAME"
    fi

    full_path="$(_cg_resolve_command_path "$cmd")" || {
        echo "[ERROR] guard: unable to resolve full path for '$cmd'." >&2
        return "$CG_ERR_NOT_FOUND"
    }

    eval "${cmd}() { \"${full_path}\" \"\$@\"; }"
}
