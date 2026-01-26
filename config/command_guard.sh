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

    # Option -p supersedes PATH with a builtin default value
    resolved="$(command -pv -- "$cmd")" || return 1
    # "command -v" worked.
    printf '%s' "$resolved"
    # Check that it's an executabla and has an absolute path
    # Fast path: if it's an executable with an absolute path, return it
    if [[ -x "$resolved" && "${resolved#/}" != "$resolved" ]]; then
        return 0
    fi

    return 1
}

# --- Public API ---------------------------------------------------------------
# Function:
#   guard
# Description:
#   Defines a function named <command> that shadows the external command and
#   dispatches to it by full path with all arguments forwarded.
# Usage:
#   guard [-q] [--] [command ...]
# Options:
#   -q  Quiet mode: suppress warnings when guard is called without any commands
#   --  End of options, start of command list
# Examples:
#   guard uname
#   guard uname date hostname
#   guard -q  # no warning
#   guard -- uname -login  # Treats "-login" as a command name
# Errors:
#   CG_ERR_MISSING_COMMAND, CG_ERR_INVALID_NAME, CG_ERR_NOT_FOUND
# Notes:
#   Uses a restricted PATH ("/usr/bin:/bin") in a subshell to resolve the command.
#   This avoids resolving through user-controlled PATH entries.
#
#   This function uses eval to define the shadowing function; input is validated
#   to be a legal Bash identifier before eval is invoked.
guard() {
    local quiet=false
    local -a commands=()

    # Parse options
    OPTIND=1
    while getopts ":q" opt; do
        case $opt in
            q) quiet=true ;;
            \?) echo "[ERROR] guard: unknown option '-$OPTARG'" >&2; return "$CG_ERR_INVALID_NAME" ;;
        esac
    done
    shift $((OPTIND - 1))

    # Remaining args are commands
    commands=("$@")

    # Handle zero commands as a no-op with optional warning
    if [ ${#commands[@]} -eq 0 ]; then
        if [ "$quiet" = false ]; then
            echo "[WARNING] guard: no commands specified." >&2
        fi
        return 0
    fi

    # First pass: validate all commands
    local cmd full_path
    local -a valid_commands=()
    local -a full_paths=()

    for cmd in "${commands[@]}"; do
        if ! [[ "$cmd" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            echo "[ERROR] guard: invalid command identifier '$cmd'." >&2
            return "$CG_ERR_INVALID_NAME"
        fi

        full_path="$(_cg_resolve_command_path "$cmd")" || {
            if [[ "$full_path" == "$cmd" ]]; then
                # It's a builtin
                echo "[BUG] guard: '$cmd' is a builtin and should not be guarded." >&2
            elif [[ "$full_path" == alias\ * ]]; then
                # it's an alias
                echo "[BUG] guard: '$cmd' is an alias and should not be used in scripts." >&2
            else
                echo "[ERROR] guard: unable to resolve full path for '$cmd'. Use the full path." >&2
            fi
            [[ "$BASHPID" != "$$" ]] && exit $CG_ERR_NOT_FOUND || return $CG_ERR_NOT_FOUND
        }
        valid_commands+=("$cmd")
        full_paths+=("$full_path")
    done

    # Second pass: create functions for all valid commands
    local i
    for ((i=0; i<${#valid_commands[@]}; i++)); do
        eval "${valid_commands[i]}() { \"${full_paths[i]}\" \"\$@\"; }"
    done
}
