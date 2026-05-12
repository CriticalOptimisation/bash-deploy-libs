#!/bin/bash
# File: config/command_guard.sh
# Description: Guard external commands by shadowing them with full-path wrappers.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__COMMAND_GUARD_SH_INCLUDED:-} ]] && __COMMAND_GUARD_SH_INCLUDED=1 || return 0

# --- Public error codes --------------------------------------------------------
# shellcheck disable=SC2034  # used by test assertions, not by library code
readonly CG_ERR_PATH_VIOLATION=1
readonly CG_ERR_NOT_FOUND=3
readonly CG_ERR_INVALID_NAME=5
readonly CG_ERR_MISSING_ARGUMENT=8
readonly CG_ERR_SYNTAX_ERROR=9

# --- Compiled-in default PATH (discovered once; used by cg_unsafe) ------------
# shellcheck disable=SC2016  # $PATH intentionally unexpanded here; expands inside the subshell
_CG_DEFAULT_PATH="$(unset PATH; "$(command -pv bash)" -c 'echo "$PATH"')"
readonly _CG_DEFAULT_PATH

# --- Public resolvers ---------------------------------------------------------

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
    if [[ $# -ne 1 ]]; then
        echo "[ERROR] cg_safe_resolver: accepts exactly one argument (command name); use -r with cg_path_resolver to pass options." >&2
        return "$CG_ERR_SYNTAX_ERROR"
    fi
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
    # Option processing without getopts
    while [[ $# -gt 1 ]]; do
        case "$1" in
            -d) extra_path="${extra_path:+$extra_path:}$2"; shift 2 ;;
            -s) extra_path="${extra_path:+$extra_path:}$_CG_DEFAULT_PATH"; shift ;;
            *)  echo "[ERROR] cg_path_resolver: unexpected token '$1'; use -d for each directory or -s for the safe path." >&2
                return "$CG_ERR_SYNTAX_ERROR" ;;
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

# --- Internal helpers ---------------------------------------------------------

# Function:
#   _cg_guard_resolve
# Description:
#   Resolve <cmd_name> via <resolver> with forwarded options.
#   Prints the resolved path to stdout (even on failure, so the caller can
#   inspect it). Prints a diagnostic to stderr and returns the resolver's
#   error code on failure — CG_ERR_NOT_FOUND for missing commands,
#   CG_ERR_SYNTAX_ERROR when the resolver rejects the call.
# Usage:
#   _cg_guard_resolve <resolver> [forward_opts...] <cmd_name>
_cg_guard_resolve() {
    local _cgr_resolver="$1"; shift
    local _cgr_name="${!#}"
    local _cgr_path _cgr_rc
    _cgr_path="$("$_cgr_resolver" "$@")"
    _cgr_rc=$?
    printf '%s' "$_cgr_path"
    if [[ $_cgr_rc -ne 0 ]]; then
        if [[ "$_cgr_path" == "$_cgr_name" ]]; then
            echo "[BUG] cg_guard: '$_cgr_name' is a builtin and should not be guarded." >&2
        elif [[ "$_cgr_path" == alias\ * ]]; then
            echo "[BUG] cg_guard: '$_cgr_name' is an alias and should not be used in scripts." >&2
        else
            echo "[ERROR] cg_guard: unable to resolve full path for '$_cgr_name'. Use the full path." >&2
        fi
        return "$_cgr_rc"
    fi
}

# Function:
#   _cg_unpack_args
# Description:
#   Unpack a packed-value string into the caller-visible array _cg_unpacked.
#   Convention: first char in [a-zA-Z0-9_-] → single element, value as-is.
#   Empty string → one empty-string element. Any other first character is
#   the separator: strip it, split remainder on it, preserving empty segments.
#   Examples: ":−p" → ("-p"); ":-p:" → ("-p" ""); ":-p::" → ("-p" "" "").
# Usage:
#   local -a _cg_unpacked; _cg_unpack_args <packed>
_cg_unpack_args() {
    local _cgu_val="$1"
    _cg_unpacked=()
    if [[ -z "$_cgu_val" ]]; then
        _cg_unpacked=("")
        return 0
    fi
    local _cgu_sep="${_cgu_val:0:1}"
    if [[ "$_cgu_sep" =~ [a-zA-Z0-9_-] ]]; then
        _cg_unpacked=("$_cgu_val")
        return 0
    fi
    local _cgu_rest="${_cgu_val:1}"
    [[ -z "$_cgu_rest" ]] && return 0
    mapfile -t _cg_unpacked <<< "${_cgu_rest//"$_cgu_sep"/$'\n'}"
}

# Function:
#   _cg_guard_mkfname
# Description:
#   Dispatch to the active name filter, unpacking the packed p-value first.
#   The filter receives: [unpacked_p_params...] <bare-name>.
# Usage:
#   _cg_guard_mkfname <filter_fn> <packed_p_value> <bare-name>
_cg_guard_mkfname() {
    local -a _cg_unpacked
    _cg_unpack_args "$2"
    "$1" "${_cg_unpacked[@]}" "$3"
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
#   Typical use: wrapping init of third-party (unsafe) libraries that call
#   external commands not guarded by cg_guard. cg_guard with cg_path_resolver
#   also works inside cg_unsafe (e.g. to guard tools installed via apt or snap).
# Usage:
#   cg_unsafe <fn> [args...]
cg_unsafe() {
    local PATH="$_CG_DEFAULT_PATH"
    "$@"
}

# Function:
#   cg_command_not_found_handle
# Description:
#   Public handler for the command_not_found_handle hook. When CG_DEBUG is
#   set (non-empty), prints a [WARNING] and a cg_guard suggestion to stderr.
#   Always returns 127. Applications can chain to this from their own handler.
# Usage:
#   cg_command_not_found_handle <cmd>
cg_command_not_found_handle() {
    local cmd="$1"
    if [[ -n "${CG_DEBUG:-}" ]]; then
        local resolved
        resolved="$(command -pv "$cmd" 2>/dev/null)"
        if [[ -n "$resolved" ]]; then
            echo "[WARNING] cg_guard: non-guarded command: $cmd" >&2
            echo "[WARNING] Suggestion: cg_guard ${cmd}=${resolved}" >&2
        else
            echo "[WARNING] cg_guard: non-guarded command not found: $cmd" >&2
        fi
    fi
    return 127
}

# Install command_not_found_handle only if unclaimed.
if ! declare -f command_not_found_handle >/dev/null 2>&1; then
    command_not_found_handle() { cg_command_not_found_handle "$@"; }
fi

# Function:
#   cg_mkfname_prefix
# Description:
#   Default name filter used by cg_guard. Prepends a fixed prefix to the
#   bare command name and validates the result as a legal Bash identifier.
# Usage:
#   cg_mkfname_prefix <prefix> <bare-name>
cg_mkfname_prefix() {
    if [[ $# -ne 2 ]]; then
        echo "[ERROR] cg_mkfname_prefix: requires exactly 2 arguments (prefix, bare-name)." >&2
        return "$CG_ERR_SYNTAX_ERROR"
    fi
    local _cgp_result="${1}${2}"
    if ! [[ "$_cgp_result" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "[ERROR] cg_mkfname_prefix: '${_cgp_result}' is not a valid Bash identifier." >&2
        return "$CG_ERR_INVALID_NAME"
    fi
    printf '%s' "$_cgp_result"
}

# Function:
#   cg_search_snaps
# Description:
#   Discovers the snap binary directory and returns it as a -z-packed argument
#   suitable for passing directly to cg_guard -r cg_path_resolver.
#   Always returns 0; outputs a no-op -z string when snap is absent or broken.
# Usage:
#   cg_guard -r cg_path_resolver "$(cg_search_snaps)" <cmd>
cg_search_snaps() {
    local _cgs_noop=$'-z\x1F'
    if ! command -p snap >/dev/null 2>&1; then
        printf '%s' "$_cgs_noop"
        return 0
    fi
    local _cgs_paths
    if ! _cgs_paths="$(command -p snap debug paths 2>/dev/null)"; then
        echo "[WARNING] cg_search_snaps: 'snap debug paths' failed; snap binary directory will not be discovered." >&2
        printf '%s' "$_cgs_noop"
        return 0
    fi
    local _cgs_bin="" _cgs_line
    while IFS= read -r _cgs_line; do
        if [[ "$_cgs_line" == SNAPD_BIN=* ]]; then
            _cgs_bin="${_cgs_line#SNAPD_BIN=}"
            break
        fi
    done <<< "$_cgs_paths"
    if [[ -z "$_cgs_bin" || ! -d "$_cgs_bin" ]]; then
        echo "[WARNING] cg_search_snaps: SNAPD_BIN not found or not a directory; snap binary directory will not be discovered." >&2
        printf '%s' "$_cgs_noop"
        return 0
    fi
    printf '%s' $'-z\x1F-d\x1F'"$_cgs_bin"
}

# Function:
#   cg_guard
# Description:
#   Defines a wrapper function for each token that dispatches to the
#   resolved full path with all arguments forwarded.
# Usage:
#   cg_guard [-q] [-n <filter>] [-p <value>] [-r <resolver>] [-z <packed>] [resolver-opts] [--] [token ...]
# Options:
#   -q          Quiet: suppress warnings for zero tokens and empty -p.
#   -n filter   Use filter instead of cg_mkfname_prefix to compute wrapper
#               function names for plain-name and /abs/path tokens.
#               Has no effect on fname=... tokens. May appear at most once.
#   -p value    Pass value as parameter(s) to the name filter. For the default
#               cg_mkfname_prefix, value is the prefix string. For custom
#               filters, value is a packed parameter list. An empty -p "" with
#               the default filter emits a [WARNING] unless -q is active.
#               Has no effect on fname=... tokens. May appear at most once.
#   -r resolver Use resolver instead of cg_safe_resolver. All unrecognised
#               option flags are forwarded to the resolver; cg_guard probes the
#               resolver to determine which flags take an argument.
#               Guard options must precede resolver options.
#   -z packed   Unpack packed and inject the resulting tokens into forward_opts
#               at the current position. May be repeated; each occurrence
#               injects one independent batch. Primary use: cg_search_snaps.
#   --          End of options; required when a token name starts with -.
# Token forms:
#   fname=/abs/path  explicit fname, absolute path verbatim
#   fname=name       explicit fname, name resolved via resolver
#   /abs/path        function name = filter(prefix, basename), path verbatim
#   name             function name = filter(prefix, name), resolved via resolver
# Errors:
#   CG_ERR_INVALID_NAME      invalid Bash identifier in a token
#   CG_ERR_MISSING_ARGUMENT  cg_guard option -r, -p, -n, or -z missing argument
#   CG_ERR_NOT_FOUND         command not found or path invalid/non-executable
#   CG_ERR_SYNTAX_ERROR      relative path where absolute required; a guard option
#                            (-q, -r, -p, -n) repeated; or a forwarded option
#                            rejected by the resolver (not recognised)
# Notes:
#   Validation is all-or-nothing: no wrapper is created unless every token
#   passes validation.
cg_guard() {
    local quiet=false resolver="cg_safe_resolver" prefix="" name_filter_fn="cg_mkfname_prefix"
    local -a forward_opts=() _cg_unpacked
    local opt_q=false opt_r=false opt_p=false opt_n=false

    # Parse guard's own options with getopts; unknown flags are forwarded to
    # the resolver after an arity probe. Guard options must precede resolver
    # options: guard [-q] [-n filter] [-p value] [-r resolver] [-z packed] [resolver-opts] [--] tokens
    OPTIND=1
    while getopts ":qr:p:n:z:" opt; do
        case $opt in
            q) [[ "$opt_q" == true ]] && { echo "[ERROR] cg_guard: option -q specified more than once." >&2; return "$CG_ERR_SYNTAX_ERROR"; }
               opt_q=true; quiet=true ;;
            r) [[ "$opt_r" == true ]] && { echo "[ERROR] cg_guard: option -r specified more than once." >&2; return "$CG_ERR_SYNTAX_ERROR"; }
               opt_r=true; resolver="$OPTARG" ;;
            p) [[ "$opt_p" == true ]] && { echo "[ERROR] cg_guard: option -p specified more than once." >&2; return "$CG_ERR_SYNTAX_ERROR"; }
               opt_p=true; prefix="$OPTARG" ;;
            n) [[ "$opt_n" == true ]] && { echo "[ERROR] cg_guard: option -n specified more than once." >&2; return "$CG_ERR_SYNTAX_ERROR"; }
               opt_n=true; name_filter_fn="$OPTARG" ;;
            z) _cg_unpack_args "$OPTARG"
               forward_opts+=("${_cg_unpacked[@]}") ;;
            \?)
                local flag="-$OPTARG"
                local next="${*:OPTIND:1}"
                # When $next does not start with a dash and is not --, it is either
                # an option parameter to the resolver, or the first token to convert.
                # We test it first as an option parameter, verbatim, and reach
                # a conclusion if the resolver complains that the name to resolve is
                # missing.  If the resolver rejects the flag as a syntax error, the
                # option is not recognised and cg_guard returns immediately.
                if [[ -n "$next" && "${next:0:1}" != "-" && "$next" != "--" ]]; then
                    "$resolver" "${forward_opts[@]}" "$flag" "$next" >/dev/null 2>&1
                    local probe_rc=$?
                    if [[ $probe_rc -eq "$CG_ERR_MISSING_ARGUMENT" ]]; then
                        forward_opts+=("$flag" "$next")
                        (( OPTIND++ ))
                    elif [[ $probe_rc -eq "$CG_ERR_SYNTAX_ERROR" ]]; then
                        echo "[ERROR] cg_guard: option '$flag' is not recognised by resolver '$resolver'." >&2
                        return "$CG_ERR_SYNTAX_ERROR"
                    else
                        forward_opts+=("$flag")
                    fi
                else
                    forward_opts+=("$flag")
                fi
                ;;
            :)  echo "[ERROR] cg_guard: option -$OPTARG requires an argument." >&2
                return "$CG_ERR_MISSING_ARGUMENT" ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ "${1-}" == "--" ]] && shift

    if [[ "$opt_p" == true && -z "$prefix" && "$name_filter_fn" == "cg_mkfname_prefix" && "$quiet" != true ]]; then
        echo "[WARNING] cg_guard: -p \"\" with the default filter has no effect; omit -p or specify a non-empty prefix." >&2
    fi

    # Handle zero tokens
    if [[ $# -eq 0 ]]; then
        if [[ "$quiet" != true ]]; then
            echo "[WARNING] cg_guard: no commands specified." >&2
        fi
        return 0
    fi

    # First pass: validate all tokens (all-or-nothing)
    local token fname rhs bname full_path
    local -a valid_fnames=()
    local -a valid_paths=()

    for token in "$@"; do
        if [[ "${token:0:1}" == "/" ]]; then
            # /abs/path form — filter applied to basename
            bname="${token##*/}"
            fname="$(_cg_guard_mkfname "$name_filter_fn" "$prefix" "$bname")" || return $?
            if [[ ! -x "$token" ]]; then
                echo "[ERROR] cg_guard: unable to resolve full path for '$token'. Use the full path." >&2
                return "$CG_ERR_NOT_FOUND"
            fi
            valid_fnames+=("$fname")
            valid_paths+=("$token")

        elif [[ "$token" == *=* ]]; then
            # fname=rhs form — prefix NOT applied
            fname="${token%%=*}"
            rhs="${token#*=}"

            if ! [[ "$fname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[ERROR] cg_guard: invalid command identifier '$fname'." >&2
                return "$CG_ERR_INVALID_NAME"
            fi

            if [[ "${rhs:0:1}" == "/" ]]; then
                # Absolute path — verbatim
                if [[ ! -x "$rhs" ]]; then
                    echo "[ERROR] cg_guard: unable to resolve full path for '$fname'. Use the full path." >&2
                    return "$CG_ERR_NOT_FOUND"
                fi
                full_path="$rhs"
            elif [[ "$rhs" == */* ]]; then
                # Contains / but not absolute
                echo "[ERROR] cg_guard: '$rhs' must be an absolute path." >&2
                return "$CG_ERR_SYNTAX_ERROR"
            else
                # Plain name — resolve via resolver
                full_path="$(_cg_guard_resolve "$resolver" "${forward_opts[@]}" "$rhs")" || return $?
            fi
            valid_fnames+=("$fname")
            valid_paths+=("$full_path")

        else
            # plain name — prefix applied, resolved via resolver
            if ! [[ "$token" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[ERROR] cg_guard: invalid command identifier '$token'." >&2
                return "$CG_ERR_INVALID_NAME"
            fi

            full_path="$(_cg_guard_resolve "$resolver" "${forward_opts[@]}" "$token")" || return $?
            fname="$(_cg_guard_mkfname "$name_filter_fn" "$prefix" "$token")" || return $?
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

# Define 'guard' as a short alias for cg_guard only if unclaimed.
if ! declare -f guard >/dev/null 2>&1; then
    guard() { cg_guard "$@"; }
fi
