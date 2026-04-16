#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__HANDLE_STATE_SH_INCLUDED:-} ]] && __HANDLE_STATE_SH_INCLUDED=1 || return 0

# Source command guard for secure external command usage
# shellcheck source=config/command_guard.sh
# shellcheck disable=SC1091
source "${BASH_SOURCE%/*}/command_guard.sh"

# Library usage:
#   In an initialization function, call hs_persist_state_as_code with the names of local variables
#   that need to be preserved for later use in a cleanup function.
# Example:
#   init_function() {
#       local temp_file="/tmp/some_temp_file"
#       local resource_id="resource_123"
#       hs_persist_state_as_code "$@" temp_file resource_id
#       return 0
#   }
#   cleanup() {
#       local temp_file
#       local resource_id
#       hs_read_persisted_state "$@" temp_file resource_id  # Recreate local variables from the state string
#       # Now temp_file and resource_id are available for cleanup operations
#       rm -f "$temp_file"
#       echo "Cleaned up resource: $resource_id"
#       hs_destroy_state "$@" -- temp_file resource_id  # Ensure the state variable can be reused.
#   }
#
# Upper level usage: state=$(init_function)
#                    cleanup "$state"

guard timeout

# --- Public error codes --------------------------------------------------------
readonly HS_ERR_RESERVED_VAR_NAME=1
readonly HS_ERR_VAR_NAME_COLLISION=2
readonly HS_ERR_MULTIPLE_STATE_INPUTS=3
readonly HS_ERR_CORRUPT_STATE=4
readonly HS_ERR_INVALID_VAR_NAME=5
readonly HS_ERR_VAR_NAME_NOT_IN_STATE=6
readonly HS_ERR_STATE_VAR_UNINITIALIZED=7
readonly HS_ERR_MISSING_ARGUMENT=8

# --- hs_persist_state_as_code ----------------------------------------------------------
# Function:
#   hs_persist_state_as_code
# Description:
#   Emits a bash code snippet that, when eval'd in the receiving scope,
#   will recreate the specified local variables with their current values.
#   The emitted code checks if the variable is declared `local` in the receiving
#   scope before assigning to it, to avoid polluting global scope.
#   If the variable already exists and is non-empty in the receiving scope,
#   an error message is printed and the assignment is skipped.
# Arguments:
#   -S <statevar> - required; appends the emitted code to variable
#                   definitions found in the variable <statevar>.
#   $@ - names of local variables to persist.
# Usage examples:
#   local state
#   hs_persist_state_as_code -S state var1 var2
#   cleanup() {
#       local var1 var2
#       eval "$1"
#       # vars are available here
#   }
hs_persist_state_as_code() {
    local __existing_state=""
    local __output_state_var=""
    local __consumed_state_args=0
    _hs_resolve_state_inputs hs_persist_state_as_code __existing_state __output_state_var __consumed_state_args "$@" || return $?
    shift "$__consumed_state_args"
    # Initialize output state string
    local __output=""
    if [ -n "$__existing_state" ]; then
        __output="$__existing_state"
    fi
    local __var_name
    for __var_name in "$@"; do
        # Check that the value of __var_name is neither "__var_name" nor "__existing_state"
        if [ "$__var_name" = "__var_name" ] || [ "$__var_name" = "__existing_state" ] || [ "$__var_name" = "__output_state_var" ] || [ "$__var_name" = "__output" ]; then
            echo "[ERROR] hs_persist_state_as_code: refusing to persist reserved variable name '$__var_name'." >&2  
            return "$HS_ERR_RESERVED_VAR_NAME"
        fi
        # Detect name collisions if __existing_state is provided
        if [ -n "$__existing_state" ]; then
            # In a time-constrained subshell, declare "$__var_name" as local to capture its value
            # and attempt to restore it from "$__existing_state".
            timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -elc "
                command_not_found_handle() {
                    echo \"[ERROR] hs_persist_state_as_code: command '\$1' not found.\" >&2
                    exit 127
                }
                test_collision() {
                    local \"$__var_name\"
                    eval \"$__existing_state\" >/dev/null
                    # Check if the variable pointed to by __var_name has been initialized
                    if ! [ -z \"\${${__var_name}+x}\" ]; then
                        echo \"[ERROR] hs_persist_state_as_code: variable '$__var_name' is already defined in the state, with value '\${${__var_name}}'.\" >&2
                        exit 1
                    fi
                }
                test_collision
            " 
            local status=$?
            if [ $status -eq 124 ] || [ $status -eq 127 ] || [ $status -eq 137 ] || [ $status -eq 143 ]; then
                # Status code snippet timed out: 124 (timeout), 137 (killed), 127 (command not found), 143 (sigterm)
                echo "[ERROR] hs_persist_state_as_code: prior state is corrupted." >&2
                return $((HS_ERR_CORRUPT_STATE))
            elif [ $status -eq 1 ]; then
                return $((HS_ERR_VAR_NAME_COLLISION))
            elif [ $status -ne 0 ]; then
                echo "[ERROR] hs_persist_state_as_code: internal error while checking for variable name collision for '$__var_name'." >&2
                return $((HS_ERR_CORRUPT_STATE))
            fi
        fi
        # Check if the variable exists in the caller (local or global). We avoid
        # using `local -p` here because that only inspects locals of this
        # function, not the caller's scope. If the variable exists, capture its
        # value and emit a guarded assignment that will only set it in the
        # receiving scope if that scope has declared it `local`.
        if [ "${!__var_name+x}" ]; then
            # Get the value of the variable
            local var_value
            var_value="${!__var_name}" || eval "var_value=\"\${$__var_name}\"" || eval "var_value=\"\$$__var_name\""
            # Emit a snippet that, when eval'd in the receiving scope, will
            # restore the existing, empty local variables from the saved state.
            __snippet=$(printf "
if local -p %s >/dev/null 2>&1; then
  if [ -n \"\${%s+x}\" ] && [ -n \"\${%1s}\" ]; then
    printf \"[ERROR] local %1s already defined; refusing to overwrite\\n\" >&2
    return 1
  else
    %s=%q
  fi
fi
" "$__var_name" "$__var_name" "$__var_name" "$__var_name" "$__var_name" "$var_value")
            __output="${__output}${__snippet}"
        fi
    done
    printf -v "$__output_state_var" '%s' "$__output"
}

# --- hs_destroy_state ---------------------------------------------------------------
# Function:
#   hs_destroy_state
# Description:
#   Purge the state string from the given definitions. In the cleanup function
#   of a library, the state vector should be stripped of that library's state
#   variables, so that the init function can be called again without triggering
#   name collision errors.
# Arguments:
#   -S <statevar> - required; reads and rewrites the state held in
#                   the variable <statevar>.
#   $@ - names of local variables to destroy.
# Usage examples:
#   mylib_cleanup() {
#       hs_destroy_state -S state mylib_statevar1 mylibstatevar2
#   }
hs_destroy_state() {
    # Step 1: resolve the input/output state sources using the same -S-only
    # parsing rules as hs_persist_state_as_code. After this call:
    #   - __existing_state contains the input state snippet to transform
    #   - __output_state_var names the destination variable, if -S was used
    #   - __consumed_state_args tells us how many option arguments to discard
    #     before "$@" contains only variable names to destroy.
    local __existing_state=""
    local __output_state_var=""
    local __consumed_state_args=0
    _hs_resolve_state_inputs hs_destroy_state __existing_state __output_state_var __consumed_state_args "$@" || return $?
    shift "$__consumed_state_args"

    # Step 2: set up working variables.
    # __state_var_names will contain every variable name found in the incoming
    # persisted state. __keep_state_names will contain only the survivors, i.e.
    # variables that remain after removing the requested names.
    local __output=""
    local __var_name
    local __state_var=""
    local __state_var_found=false
    local __keep_var=""
    local __keep_state_names=""
    local -a __state_var_names=()

    # Step 3: scan the existing state snippet for persisted variable names.
    # We intentionally look only for the top-level headers emitted by
    # hs_persist_state_as_code. We do not splice the blocks directly. We only
    # discover the names here; the actual output state will be rebuilt from
    # surviving variables later.
    _hs_extract_persisted_state_var_names hs_destroy_state "$__existing_state" __state_var_names || return $?
    for __state_var in "${__state_var_names[@]}"; do
        __state_var_found=false
        for __var_name in "$@"; do
            if [[ "$__var_name" == "$__state_var" ]]; then
                __state_var_found=true
                break
            fi
        done
        if [[ "$__state_var_found" == false ]]; then
            __keep_state_names+="${__state_var}"$'\n'
        fi
    done

    # Step 5: every requested variable must actually exist in the incoming
    # state. If a requested name is absent, return HS_ERR_INVALID_VAR_NAME.
    for __var_name in "$@"; do
        __state_var_found=false
        for __state_var in "${__state_var_names[@]}"; do
            if [[ "$__state_var" == "$__var_name" ]]; then
                __state_var_found=true
                break
            fi
        done
        if [[ "$__state_var_found" == false ]]; then
            echo "[ERROR] hs_destroy_state: variable '$__var_name' is not defined in the state." >&2
            return "$HS_ERR_VAR_NAME_NOT_IN_STATE"
        fi
    done

    # Step 6: rebuild the state from scratch using only the survivor names.
    # Instead of editing the text blocks in place, run a fresh Bash subprocess
    # that:
    #   1. defines the minimal helpers needed (_hs_resolve_state_inputs and
    #      hs_persist_state_as_code plus their error-code constants),
    #   2. declares every survivor variable local,
    #   3. evals the incoming state to restore those locals,
    #   4. calls the stdout form of hs_persist_state_as_code on the survivor list.
    #
    # This avoids depending on BASH_SOURCE or on re-sourcing this file from a
    # filesystem path, which would break when handle_state.sh was obtained via
    # remote_run's virtual source mechanism.
    if [[ -n "$__keep_state_names" ]]; then
        local -a __keep_state_args=()
        while IFS= read -r __keep_var || [[ -n "$__keep_var" ]]; do
            [[ -z "$__keep_var" ]] && continue
            __keep_state_args+=("$__keep_var")
        done <<< "$__keep_state_names"

        __output=$(timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
            readonly HS_ERR_RESERVED_VAR_NAME='"$HS_ERR_RESERVED_VAR_NAME"'
            readonly HS_ERR_VAR_NAME_COLLISION='"$HS_ERR_VAR_NAME_COLLISION"'
            readonly HS_ERR_MULTIPLE_STATE_INPUTS='"$HS_ERR_MULTIPLE_STATE_INPUTS"'
            readonly HS_ERR_CORRUPT_STATE='"$HS_ERR_CORRUPT_STATE"'
            readonly HS_ERR_INVALID_VAR_NAME='"$HS_ERR_INVALID_VAR_NAME"'
            '"$(declare -f _hs_is_valid_variable_name)"'
            '"$(declare -f _hs_resolve_state_inputs)"'
            '"$(declare -f hs_persist_state_as_code)"'
            _hs_destroy_state_rebuild() {
                local __rebuild_state=$1
                shift
                local __name
                local __rebuilt_state=""
                for __name in "$@"; do
                    local "$__name"
                done
                eval "$__rebuild_state" >/dev/null
                hs_persist_state_as_code -S __rebuilt_state "$@"
                printf '%s' "$__rebuilt_state"
            }
            _hs_destroy_state_rebuild "$@"
        ' bash "$__existing_state" "${__keep_state_args[@]}")
        local __status=$?
        # Step 7: map rebuild failures to the same "corrupt prior state"
        # category used elsewhere in handle_state when we cannot safely process
        # the supplied snippet.
        if [ $__status -eq 124 ] || [ $__status -eq 127 ] || [ $__status -eq 137 ] || [ $__status -eq 143 ]; then
            echo "[ERROR] hs_destroy_state: prior state is corrupted." >&2
            return "$HS_ERR_CORRUPT_STATE"
        elif [ $__status -ne 0 ]; then
            echo "[ERROR] hs_destroy_state: internal error while rebuilding state." >&2
            return "$HS_ERR_CORRUPT_STATE"
        fi
    fi

    # Step 8: write the rebuilt state back into the named state variable.
    printf -v "$__output_state_var" '%s' "$__output"
}
# --- hs_read_persisted_state --------------------------------------------------------
# Function: 
#   hs_read_persisted_state
# Description: 
#   Emits the state string produced by `hs_persist_state_as_code` without evaluating it.
#   The state is passed by variable name and accessed via a nameref, so callers
#   do not pass the snippet by value. This function still only returns the
#   stored code snippet; callers should `eval "$(hs_read_persisted_state state)"`
#   or simply `eval "$state"` to recreate variables in the caller scope.
#   For convenience, callers may pass either `state` or `-S state`.
#   Can be called several times to extract distinct variables.
#   The referenced state variable contains a bash code snippet that assigns
#   values to existing local and empty variables in the current scope.
# Arguments:
#   $1 - name of the variable holding the state string produced by `hs_persist_state_as_code`,
#        or `-S`
#   $2 - state variable name when `$1` is `-S`
# Errors:
#   - Rejects a missing first argument.
#   - Rejects an invalid variable name.
#   - Rejects a valid variable name that does not refer to an existing,
#     non-empty state variable.
# Usage examples:
#   # direct eval
#   cleanup() {
#       local state_var="$1"
#       local -n state_ref="$state_var"
#       local temp_file resource_id
#       eval "$state_ref"
#       # vars are available here
#   }
#
#   # helper wrapper form (prints state; caller evals it in its own scope)
#   cleanup() {
#       local state="$1"
#       local temp_file resource_id
#       eval "$(hs_read_persisted_state state)"
#   }
hs_read_persisted_state() {
    # Step 1: parse hs_read_persisted_state-specific flags before delegating
    # the shared state-input handling to _hs_resolve_state_inputs.
    local __quiet=false
    while [ $# -gt 0 ] && [ "${1-}" = "-q" ]; do
        __quiet=true
        shift
    done

    if [ $# -eq 0 ]; then
        echo "[ERROR] hs_read_persisted_state: missing required state variable name." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi

    if [ "${1-}" != "-S" ]; then
        set -- -S "$@"
    fi

    # Step 2: resolve the named state variable and capture its current payload.
    # The helper validates names, enforces the presence of -S, and returns:
    #   - __existing_state: the current serialized state snippet
    #   - __output_state_var: the caller-visible variable name holding that state
    #   - __consumed_state_args: how many leading arguments belong to state input
    local __existing_state=""
    local __output_state_var=""
    local __consumed_state_args=0
    _hs_resolve_state_inputs hs_read_persisted_state __existing_state __output_state_var __consumed_state_args "$@" || return $?

    if [ -z "$__existing_state" ]; then
        echo "[ERROR] hs_read_persisted_state: state variable '$__output_state_var' is not set or is empty." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi

    # Step 3: if the caller listed variable names after the state input, restore
    # only those variables directly into the caller scope. This is the explicit
    # selective-restore API.
    if [ $# -ne "$__consumed_state_args" ]; then
        shift "$__consumed_state_args"

        local __requested_var
        local __restored_value=""
        local __restore_status=0
        for __requested_var in "$@"; do
            # Evaluate the persisted state in a short-lived Bash subprocess,
            # scoped to one requested variable, then print the resulting value
            # back to this function. The subprocess is isolated and time-bounded
            # because the persisted format is still executable Bash code.
            __restored_value=$(timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
                _hs_read_requested_state_var() {
                    local __state=$1
                    local __requested_var=$2
                    local "$__requested_var"
                    eval "$__state" >/dev/null 2>&1 || return $?
                    if [ "${!__requested_var+x}" ]; then
                        printf "%s" "${!__requested_var}"
                        return 0
                    fi
                    return 10
                }
                _hs_read_requested_state_var "$@"
            ' bash "$__existing_state" "$__requested_var")
            __restore_status=$?

            if [ $__restore_status -eq 124 ] || [ $__restore_status -eq 127 ] || [ $__restore_status -eq 137 ] || [ $__restore_status -eq 143 ]; then
                echo "[ERROR] hs_read_persisted_state: prior state is corrupted." >&2
                return "$HS_ERR_CORRUPT_STATE"
            elif [ $__restore_status -eq 10 ]; then
                if [ "$__quiet" = false ]; then
                    echo "[WARNING] hs_read_persisted_state: variable '$__requested_var' is not defined in the state." >&2
                fi
                continue
            elif [ $__restore_status -ne 0 ]; then
                echo "[ERROR] hs_read_persisted_state: internal error while restoring '$__requested_var'." >&2
                return "$HS_ERR_CORRUPT_STATE"
            fi

            # Write the restored value back into the caller's variable by name.
            local -n __requested_var_ref="$__requested_var"
            __requested_var_ref="$__restored_value"
        done
        return 0
    fi

    # Step 4: otherwise, generate a safe, local probe snippet instead of
    # returning the raw persisted code. The snippet checks which matching local
    # variables are currently declared and unset in the caller, then reenters
    # hs_read_persisted_state with an explicit variable list. This avoids asking
    # callers to eval arbitrary transmitted state directly in the common case.
    local -a __probe_state_names=()
    _hs_extract_persisted_state_var_names hs_read_persisted_state "$__existing_state" __probe_state_names || return $?

    # Emit a compact Bash snippet that rebuilds the requested-variable list from
    # the caller's local scope and then reenters this function in quiet mode.
    local __probe_snippet=$'local -a __hs_read_requested_vars=()\n'
    local __probe_var
    for __probe_var in "${__probe_state_names[@]}"; do
        printf -v __probe_snippet '%sif local -p %s >/dev/null 2>&1 && [ -z "${%s}" ]; then __hs_read_requested_vars+=(%s); fi\n' \
            "$__probe_snippet" "$__probe_var" "$__probe_var" "$__probe_var"
    done
    printf -v __probe_snippet '%sif [ ${#__hs_read_requested_vars[@]} -gt 0 ]; then\n  hs_read_persisted_state -S %q "${__hs_read_requested_vars[@]}"\nfi\n' \
        "$__probe_snippet" "$__output_state_var"

    printf '%s' "$__probe_snippet"
}

# --- Utility functions --------------------------------------------------------

# Function:
#   _hs_is_valid_variable_name
# Description:
#   Returns success if the argument is a syntactically valid Bash variable name.
# Arguments:
#   $1 - candidate variable name
# Returns:
#   0 if the name is valid, 1 otherwise.
_hs_is_valid_variable_name() {
    [[ "${1-}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# Function:
#   _hs_resolve_state_inputs
# Description:
#   Parses the `-S <statevar>` option for state-oriented helpers and resolves
#   the current state from the named variable. Parsed results are returned to
#   the caller through variable names passed as parameters.
# Arguments:
#   $1 - caller function name, used in error messages; must be a valid Bash name
#   $2 - name of the variable that will receive the current state value; must be a valid Bash name
#   $3 - name of the variable that will receive the destination state variable name; must be a valid Bash name
#   $4 - name of the variable that will receive the number of consumed option arguments; must be a valid Bash name
#   $5 - first variable name to process or `-S`
#   $6... - additional variable names to process, with `-S <statevar>` required somewhere in the argument list
# Returns:
#   0 on success.
#   `HS_ERR_MISSING_ARGUMENT` if fewer than 6 arguments are provided.
#   `HS_ERR_STATE_VAR_UNINITIALIZED` if no `-S <statevar>` option is provided.
#   `HS_ERR_INVALID_VAR_NAME` if `-S` is followed by an invalid variable name.
# Usage:
#   local existing_state="" output_state_var="" consumed_state_args=0
#   _hs_resolve_state_inputs my_helper existing_state output_state_var consumed_state_args "$@" || return $?
_hs_resolve_state_inputs() {
    if [ $# -lt 6 ]; then
        echo "[ERROR] _hs_resolve_state_inputs: missing required arguments; expected at least 6 parameters." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi
    local __arg
    for __arg in "$1" "$2" "$3" "$4"; do
        if ! _hs_is_valid_variable_name "$__arg"; then
            echo "[ERROR] _hs_resolve_state_inputs: invalid variable name '$__arg'." >&2
            return "$HS_ERR_INVALID_VAR_NAME"
        fi
    done
    local __caller_name=$1
    local -n __existing_state_ref=$2
    local -n __output_state_var_ref=$3
    local -n __consumed_count_ref=$4
    shift 4

    __existing_state_ref=""
    __output_state_var_ref=""
    __consumed_count_ref=0

    local -a __args=("$@")
    local __arg_count=${#__args[@]}
    local __last_separator_index=-1
    local __i=0
    local __parse_limit=$__arg_count

    # If one or more `--` markers are present, the last one separates the
    # forwarded helper options from the explicit list of variable names.
    for ((__i = 0; __i < __arg_count; __i++)); do
        if [[ "${__args[__i]}" == "--" ]]; then
            __last_separator_index=$__i
        fi
    done

    if (( __last_separator_index >= 0 )); then
        __consumed_count_ref=$((__last_separator_index + 1))
        __parse_limit=$__last_separator_index
    else
        __consumed_count_ref=2
    fi

    # Before the effective separator, only helper options are recognized.
    # Any other forwarded arguments belong to the caller and are ignored here.
    for ((__i = 0; __i < __parse_limit; __i++)); do
        case "${__args[__i]}" in
            -S)
                if (( __i + 1 >= __parse_limit )); then
                    echo "[ERROR] ${__caller_name}: missing required state variable name for -S option." >&2
                    return "$HS_ERR_MISSING_ARGUMENT"
                fi
                __output_state_var_ref="${__args[__i + 1]}"
                if ! _hs_is_valid_variable_name "$__output_state_var_ref"; then
                    echo "[ERROR] ${__caller_name}: invalid variable name '$__output_state_var_ref' for -S option." >&2
                    return "$HS_ERR_INVALID_VAR_NAME"
                fi
                ((__i++))
                ;;
        esac
    done

    # After the effective separator, every token is part of the variable list.
    # Without a separator, this validates the traditional trailing "$@" list.
    for ((__i = __consumed_count_ref; __i < __arg_count; __i++)); do
        if ! _hs_is_valid_variable_name "${__args[__i]}"; then
            echo "[ERROR] ${__caller_name}: invalid variable name '${__args[__i]}'." >&2
            return "$HS_ERR_INVALID_VAR_NAME"
        fi
    done

    if [ -z "$__output_state_var_ref" ]; then
        echo "[ERROR] ${__caller_name}: state variable is uninitialized; missing required -S <statevar> option." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi

    eval "__existing_state_ref=\${$__output_state_var_ref-}"
}

# Function:
#   _hs_extract_persisted_state_var_names
# Description:
#   Parses a code-snippet state produced by `hs_persist_state_as_code` and
#   extracts the variable names declared by its guarded `if local -p VAR ...`
#   blocks. Results are returned through an array nameref.
# Arguments:
#   $1 - caller function name, used in error messages
#   $2 - state snippet string to inspect
#   $3 - name of the array variable that will receive extracted variable names
# Returns:
#   0 on success.
#   `HS_ERR_INVALID_VAR_NAME` if one of the first or third arguments is not a
#   valid Bash variable name.
#   `HS_ERR_CORRUPT_STATE` if the snippet contains an invalid persisted variable
#   name or if the state is non-empty but contains no persisted variable blocks.
# Usage:
#   local -a state_var_names=()
#   _hs_extract_persisted_state_var_names my_helper "$state" state_var_names || return $?
_hs_extract_persisted_state_var_names() {
    if [ $# -ne 3 ]; then
        echo "[ERROR] _hs_extract_persisted_state_var_names: expected exactly 3 arguments." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi
    if ! _hs_is_valid_variable_name "$1" || ! _hs_is_valid_variable_name "$3"; then
        echo "[ERROR] _hs_extract_persisted_state_var_names: invalid variable name '$1' or '$3'." >&2
        return "$HS_ERR_INVALID_VAR_NAME"
    fi

    local __caller_name=$1
    local __state=$2
    local -n __out_names_ref=$3
    local __line=""
    local __state_var_name=""

    __out_names_ref=()
    while IFS= read -r __line || [[ -n "$__line" ]]; do
        if [[ "$__line" == "if local -p "* ]]; then
            __state_var_name=${__line#if local -p }
            __state_var_name=${__state_var_name%% *}
            if ! _hs_is_valid_variable_name "$__state_var_name"; then
                echo "[ERROR] ${__caller_name}: prior state is corrupted." >&2
                return "$HS_ERR_CORRUPT_STATE"
            fi
            __out_names_ref+=("$__state_var_name")
        fi
    done <<< "$__state"

    if [[ -n "$__state" && ${#__out_names_ref[@]} -eq 0 ]]; then
        echo "[ERROR] ${__caller_name}: prior state is corrupted." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi
}

# Function:
#    hs_get_pid_of_subshell
# Description:
#    Returns the PID of the current subshell that works in conjunction with hs_echo to
#    ensure output is properly captured and redirected to whatever stdout was when the
#    library was sourced.
# Usage:
#    pid=$(hs_get_pid_of_subshell)
# Return status:
#    0 - Success
#    1 - Internal error: hs_cleanup_output not defined or doesn't have the expected format.
hs_get_pid_of_subshell() {
    # Extract the PID of the background reader process from the function definition
    local func_def
    func_def=$(declare -f hs_cleanup_output)
    local pid
    pid=${func_def##*wait }
    # The above string substitution will just return $func_det without an error if "wait " is not found.
    if [ "$pid" = "$func_def" ]; then
        echo "hs_cleanup_output function not found or has unexpected format" >&2
        return 1
    fi
    pid=${pid%%[^0-9]*}
    printf '%s' "$pid"
}

# Note: Remember to call hs_cleanup at the end of your main script to clean up resources.
