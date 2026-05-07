#!/bin/bash
# File: config/command_guard.sh
# Description: Guard external commands by shadowing them with full-path wrappers.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__COMMAND_GUARD_SH_INCLUDED:-} ]] && __COMMAND_GUARD_SH_INCLUDED=1 || return 0

# --- Public error codes --------------------------------------------------------
readonly CG_ERR_PATH_VIOLATION=1
readonly CG_ERR_INVALID_NAME=2
readonly CG_ERR_NOT_FOUND=3
readonly CG_ERR_MISSING_ARGUMENT=4

# --- Compiled-in default PATH (discovered once; used by cg_unsafe) ------------
_CG_DEFAULT_PATH="$(unset PATH; "$(command -pv bash)" -c 'echo "$PATH"')"
readonly _CG_DEFAULT_PATH

# --- Internal helpers ---------------------------------------------------------

# Function:
#   cg_safe_resolver
# Description:
#   Default resolver: resolves a command name to its absolute path using
#   command -pv (POSIX default PATH, independent of $PATH).
#   Prints the command -pv output (even on failure, so guard can diagnose
#   builtins and aliases). Accepts no options; returns CG_ERR_MISSING_ARGUMENT
#   when called with no arguments (required by the resolver protocol).
# Usage:
#   cg_safe_resolver <cmd-name>
cg_safe_resolver() {
    [[ $# -eq 0 ]] && return "$CG_ERR_MISSING_ARGUMENT"
    [[ $# -ne 1 ]] && return "$CG_ERR_NOT_FOUND"
    local cmd="$1"
    local resolved
    resolved="$(command -pv -- "$cmd")" || return "$CG_ERR_NOT_FOUND"
    printf '%s' "$resolved"
    [[ -x "$resolved" && "${resolved:0:1}" == "/" ]] || return "$CG_ERR_NOT_FOUND"
}

# Function:
#   cg_path_resolver
# Description:
#   Extended resolver: builds a local PATH from -d options, then resolves
#   via command -v. The -d option may be repeated; its value may be a single
#   directory or a colon-separated list of directories.
#   Prints the command -v output (even on failure). Returns
#   CG_ERR_MISSING_ARGUMENT when called with no command name.
# Usage:
#   cg_path_resolver [-d dir-or-colon-list] ... <cmd-name>
cg_path_resolver() {
    local extra_path=""
    while [[ $# -gt 1 ]]; do
        case "$1" in
            -d) extra_path="${extra_path:+$extra_path:}$2"; shift 2 ;;
            *)  return "$CG_ERR_NOT_FOUND" ;;
        esac
    done
    [[ $# -eq 0 ]] && return "$CG_ERR_MISSING_ARGUMENT"
    local cmd="$1"
    local PATH="$extra_path"
    local resolved
    resolved="$(command -v -- "$cmd" 2>/dev/null)"
    printf '%s' "$resolved"
    [[ -x "$resolved" && "${resolved:0:1}" == "/" ]] || return "$CG_ERR_NOT_FOUND"
}

# --- Public API ---------------------------------------------------------------

# Function:
#   cg_safe_run
# Description:
#   Executes a declared Bash function under a restricted, read-only PATH.
#   Any attempt to assign to PATH inside the function (or its callees)
#   fails with a readonly-assignment error (CG_ERR_PATH_VIOLATION).
#   Unguarded external commands fail with exit 127 (command not found).
# Usage:
#   cg_safe_run <fn> [args...]
cg_safe_run() {
    declare -f "$1" >/dev/null 2>&1 || {
        echo "[ERROR] cg_safe_run: '$1' is not a function." >&2
        return "$CG_ERR_INVALID_NAME"
    }
    local -r PATH="/nonexistent-${SRANDOM:-${-}${RANDOM}}"
    "$@"
}

# Function:
#   cg_unsafe
# Description:
#   Executes a function with a writable local PATH set to the compiled-in
#   Bash default. Use inside cg_safe_run to allow library guard calls.
#   The local PATH in cg_unsafe shadows the local -r PATH from cg_safe_run.
# Usage:
#   cg_unsafe <fn> [args...]
cg_unsafe() {
    local PATH="$_CG_DEFAULT_PATH"
    "$@"
}

# Function:
#   cg_command_not_found_handler
# Description:
#   Public handler for the command_not_found_handle hook. When CG_DEBUG is
#   set (non-empty), prints a [WARNING] and a guard suggestion to stderr.
#   Always returns 127. Applications can chain to this from their own handler.
# Usage:
#   cg_command_not_found_handler <cmd>
cg_command_not_found_handler() {
    local cmd="$1"
    if [[ -n "${CG_DEBUG:-}" ]]; then
        local resolved
        resolved="$(command -pv "$cmd" 2>/dev/null)"
        if [[ -n "$resolved" ]]; then
            echo "[WARNING] guard: non-guarded command: $cmd" >&2
            echo "[WARNING] Suggestion: guard ${cmd}=${resolved}" >&2
        else
            echo "[WARNING] guard: non-guarded command not found: $cmd" >&2
        fi
    fi
    return 127
}

# Install command_not_found_handle only if unclaimed.
if ! declare -f command_not_found_handle >/dev/null 2>&1; then
    command_not_found_handle() { cg_command_not_found_handler "$@"; }
fi

# Function:
#   guard
# Description:
#   Defines a wrapper function for each token that dispatches to the
#   resolved full path with all arguments forwarded.
# Usage:
#   guard [-q] [-p <prefix>] [-r <resolver>] [resolver-opts] [--] [token ...]
# Options:
#   -q          Quiet: suppress warnings for zero tokens.
#   -p prefix   Prepend prefix to generated function names for plain-name
#               and /abs/path tokens. Has no effect on fname=... tokens.
#   -r resolver Use resolver instead of cg_safe_resolver. All unrecognised
#               option flags are forwarded to the resolver; guard probes the
#               resolver to determine which flags take an argument.
#               Guard options must precede resolver options.
#   --          End of options; required when a token name starts with -.
# Token forms:
#   fname=/abs/path  explicit fname, absolute path verbatim
#   fname=name       explicit fname, name resolved via resolver
#   /abs/path        function name = <prefix>basename, path verbatim
#   name             function name = <prefix>name, resolved via resolver
# Errors:
#   CG_ERR_INVALID_NAME  invalid identifier or unrecognised guard option
#   CG_ERR_NOT_FOUND     command not found or path invalid/non-executable
# Notes:
#   Validation is all-or-nothing: no wrapper is created unless every token
#   passes validation.
guard() {
    local quiet=false resolver="cg_safe_resolver" prefix=""
    local -a forward_opts=()

    # Parse guard's own options with getopts; unknown flags are forwarded to
    # the resolver after an arity probe. Guard options must precede resolver
    # options: guard [-q] [-p prefix] [-r resolver] [resolver-opts] [--] tokens
    OPTIND=1
    while getopts ":qr:p:" opt; do
        case $opt in
            q) quiet=true ;;
            r) resolver="$OPTARG" ;;
            p) prefix="$OPTARG" ;;
            \?)
                local flag="-$OPTARG"
                local next="${@:OPTIND:1}"
                if [[ -n "$next" && "${next:0:1}" != "-" && "$next" != "--" ]]; then
                    "$resolver" "${forward_opts[@]}" "$flag" "$next" >/dev/null 2>&1
                    if [[ $? -eq "$CG_ERR_MISSING_ARGUMENT" ]]; then
                        forward_opts+=("$flag" "$next")
                        (( OPTIND++ ))
                    else
                        forward_opts+=("$flag")
                    fi
                else
                    forward_opts+=("$flag")
                fi
                ;;
            :)  echo "[ERROR] guard: option -$OPTARG requires an argument." >&2
                return "$CG_ERR_INVALID_NAME" ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ "${1-}" == "--" ]] && shift

    # Handle zero tokens
    if [[ $# -eq 0 ]]; then
        if [[ "$quiet" != true ]]; then
            echo "[WARNING] guard: no commands specified." >&2
        fi
        return 0
    fi

    # First pass: validate all tokens (all-or-nothing)
    local token fname rhs bname full_path
    local -a valid_fnames=()
    local -a valid_paths=()

    for token in "$@"; do
        if [[ "${token:0:1}" == "/" ]]; then
            # /abs/path form — prefix applied to basename
            bname="${token##*/}"
            fname="${prefix}${bname}"
            if ! [[ "$fname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[ERROR] guard: '$bname' is not a valid identifier; use the 'fname=${token}' form." >&2
                return "$CG_ERR_INVALID_NAME"
            fi
            if [[ ! -x "$token" ]]; then
                echo "[ERROR] guard: unable to resolve full path for '$token'. Use the full path." >&2
                [[ "$BASHPID" != "$$" ]] && exit "$CG_ERR_NOT_FOUND" || return "$CG_ERR_NOT_FOUND"
            fi
            valid_fnames+=("$fname")
            valid_paths+=("$token")

        elif [[ "$token" == *=* ]]; then
            # fname=rhs form — prefix NOT applied
            fname="${token%%=*}"
            rhs="${token#*=}"

            if ! [[ "$fname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[ERROR] guard: invalid command identifier '$fname'." >&2
                return "$CG_ERR_INVALID_NAME"
            fi

            if [[ "${rhs:0:1}" == "/" ]]; then
                # Absolute path — verbatim
                if [[ ! -x "$rhs" ]]; then
                    echo "[ERROR] guard: unable to resolve full path for '$fname'. Use the full path." >&2
                    [[ "$BASHPID" != "$$" ]] && exit "$CG_ERR_NOT_FOUND" || return "$CG_ERR_NOT_FOUND"
                fi
                full_path="$rhs"
            elif [[ "$rhs" == */* ]]; then
                # Contains / but not absolute
                echo "[ERROR] guard: '$rhs' must be an absolute path." >&2
                [[ "$BASHPID" != "$$" ]] && exit "$CG_ERR_NOT_FOUND" || return "$CG_ERR_NOT_FOUND"
            else
                # Plain name — resolve via resolver
                full_path="$("$resolver" "${forward_opts[@]}" "$rhs")" || {
                    if [[ "$full_path" == "$rhs" ]]; then
                        echo "[BUG] guard: '$rhs' is a builtin and should not be guarded." >&2
                    elif [[ "$full_path" == alias\ * ]]; then
                        echo "[BUG] guard: '$rhs' is an alias and should not be used in scripts." >&2
                    else
                        echo "[ERROR] guard: unable to resolve full path for '$rhs'. Use the full path." >&2
                    fi
                    [[ "$BASHPID" != "$$" ]] && exit "$CG_ERR_NOT_FOUND" || return "$CG_ERR_NOT_FOUND"
                }
            fi
            valid_fnames+=("$fname")
            valid_paths+=("$full_path")

        else
            # plain name — prefix applied, resolved via resolver
            if ! [[ "$token" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[ERROR] guard: invalid command identifier '$token'." >&2
                return "$CG_ERR_INVALID_NAME"
            fi

            full_path="$("$resolver" "${forward_opts[@]}" "$token")" || {
                if [[ "$full_path" == "$token" ]]; then
                    echo "[BUG] guard: '$token' is a builtin and should not be guarded." >&2
                elif [[ "$full_path" == alias\ * ]]; then
                    echo "[BUG] guard: '$token' is an alias and should not be used in scripts." >&2
                else
                    echo "[ERROR] guard: unable to resolve full path for '$token'. Use the full path." >&2
                fi
                [[ "$BASHPID" != "$$" ]] && exit "$CG_ERR_NOT_FOUND" || return "$CG_ERR_NOT_FOUND"
            }
            fname="${prefix}${token}"
            valid_fnames+=("$fname")
            valid_paths+=("$full_path")
        fi
    done

    # Second pass: create wrapper functions
    local i
    for ((i=0; i<${#valid_fnames[@]}; i++)); do
        eval "${valid_fnames[i]}() { \"${valid_paths[i]}\" \"\$@\"; }"
    done
}
