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
#   In an initialization function, call hs_persist_state with the names of local variables
#   that need to be preserved for later use in a cleanup function.
# Example:
#   init_function() {
#       local temp_file="/tmp/some_temp_file"
#       local resource_id="resource_123"
#       hs_persist_state temp_file resource_id
#       exit 0
#   }
#   cleanup() {
#       local temp_file
#       local resource_id
#       eval "$1"  # Recreate local variables from the state string
#       # Now temp_file and resource_id are available for cleanup operations
#       rm -f "$temp_file"
#       echo "Cleaned up resource: $resource_id"
#   }
#
# Upper level usage: state=$(init_function)
#                    cleanup "$state"

guard mkfifo rm timeout

# --- logging from $(command) using a FIFO ---------------------------------------
# This section sets up a FIFO and a background reader process to allow functions
# to log messages to the main script's stdout/stderr even when they are called
# from subshells (e.g., inside `$(...)` command substitutions). Functions can
# use `hs_echo "message"` to send messages to the main script's output.

# Function: 
#   _hs_set_up_logging
# Description:
#   Sets up a FIFO and background reader process for logging.
#   The background reader must start before any I/O redirection occurs. This
#   is why it is called at the end of this file, so that when this file is sourced,
#   the logging is set up.
# Usage:
#   Do not call directly; called automatically when this file is sourced.
#   When done with the library, call `hs_cleanup_output` to terminate the background reader
#   or else a 5 seconds idle timeout will occur.
hs_setup_output_to_stdout() {
    # Test if already set up
    if hs_get_pid_of_subshell >/dev/null 2>&1; then
        echo "[WARN] hs_setup_output_to_stdout: already set up; skipping." >&2
        return 0
    fi
    # Create a FIFO using a proper temporary file and file descriptor 3 
    fifo_file=$(mktemp -u)
    mkfifo "$fifo_file"
    # Redirect fd 3 into the FIFO
    exec {_hs_fifo_fd}<> "$fifo_file"
    # Make file disappear immediately. The FIFO remains accessible via fd 3.
    rm "$fifo_file"
    # Kill token
    _hs_fifo_kill_token="hs_kill_${$}_$RANDOM_$RANDOM"
    _hs_fifo_idle_limit=5  # seconds before self-termination

    # Run a background task that reads from the FIFO and displays messages
    (
        idle=0

        while true; do
            line=''

            if IFS= read -t 1 -r line <&"${_hs_fifo_fd}"; then
                # Received a line; reset idle counter
                idle=0
                # Self-terminate on the exact magic token
                if [ "${line:-}" = "${_hs_fifo_kill_token}" ]; then
                    break
                fi
                echo "$line"
            else
                # read timed out or encountered EOF/error - increment idle counter
                idle=$((idle + 1))
                if [ "$idle" -ge "$_hs_fifo_idle_limit" ]; then
                    break
                fi
                # continue to wait
            fi
        done
        # Dismantle FIFO: close fd
        exec {_hs_fifo_fd}>&-
    ) & _hs_fifo_reader_pid=$!
 
    # Function:
    #   hs_cleanup_output, or redefined globally with the kill token embedded.
    # Description:
    #   Sends the magic kill token to the logging FIFO to terminate the background reader.
    #   Waits for the background reader to exit and redefines itself to a no-op.
    #   Redefines hs_echo to a simple echo.
    # Parameters:
    #   None
    printf -v _hs_qtoken '%q' "$_hs_fifo_kill_token"
    eval "hs_cleanup_output() {
        if hs_echo $_hs_qtoken ; then
            wait $_hs_fifo_reader_pid 2>/dev/null
            hs_cleanup_output() { :; }
            hs_echo() { echo \"\$*\" ; }
        fi
        return 0
    }"
        
    # Function:
    #   hs_echo
    # Description:
    #   Writes messages to the logging FIFO for display in the main script's stdout.
    #   Specifically designed to work inside subshells called via `$(...)`.
    #   Mimic Bash echo argument concatenation behavior.
    #   Here IFS acts on "$*" expansion to insert spaces between arguments.
    # Arguments:
    #   $* - echo options -neE or message parts to echo
    eval "hs_echo() {
        IFS=\" \" echo \"\$*\" >&\"${_hs_fifo_fd}\"
    }"
}

# --- Public error codes --------------------------------------------------------
readonly HS_ERR_RESERVED_VAR_NAME=1
readonly HS_ERR_VAR_NAME_COLLISION=2
readonly HS_ERR_MULTIPLE_STATE_INPUTS=3
readonly HS_ERR_CORRUPT_STATE=4
readonly HS_ERR_INVALID_VAR_NAME=5
readonly HS_ERR_VAR_NAME_NOT_IN_STATE=6

# _hs_resolve_state_inputs <caller_name> <existing_state_var> <output_state_var> <consumed_count_var> [args...]
# Parses -s/-S options for state-oriented helpers and resolves the prior state
# from either the explicit -s payload or the named -S variable. The caller
# receives the parsed values via the variable names passed in arguments 2 and 3,
# plus the number of consumed option arguments in argument 4.
_hs_resolve_state_inputs() {
    local __caller_name=$1
    local __existing_state_ref=$2
    local __output_state_var_ref=$3
    local __consumed_count_ref=$4
    local __consumed_count=0
    local __output_state_var_name=""
    shift 4

    printf -v "$__existing_state_ref" '%s' ""
    printf -v "$__output_state_var_ref" '%s' ""
    printf -v "$__consumed_count_ref" '%s' "0"

    while [ $# -gt 0 ]; do
        case "$1" in
            -s)
                shift
                __consumed_count=$((__consumed_count + 1))
                printf -v "$__existing_state_ref" '%s' "$1"
                shift
                __consumed_count=$((__consumed_count + 1))
                ;;
            -S)
                shift
                __consumed_count=$((__consumed_count + 1))
                printf -v "$__output_state_var_ref" '%s' "$1"
                __output_state_var_name="${!__output_state_var_ref}"
                if ! [[ "$__output_state_var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                    echo "[ERROR] ${__caller_name}: invalid variable name '$__output_state_var_name' for -S option." >&2
                    return "$HS_ERR_INVALID_VAR_NAME"
                fi
                shift
                __consumed_count=$((__consumed_count + 1))
                ;;
            *)
                break
                ;;
        esac
    done

    __output_state_var_name="${!__output_state_var_ref}"

    if [ -n "$__output_state_var_name" ] && [ -n "${!__existing_state_ref}" ]; then
        echo "[ERROR] ${__caller_name}: cannot pass prior state using both -s and -S options simultaneously." >&2
        return "$HS_ERR_MULTIPLE_STATE_INPUTS"
    fi

    if [ -n "$__output_state_var_name" ]; then
        printf -v "$__existing_state_ref" '%s' "${!__output_state_var_name}"
    fi

    printf -v "$__consumed_count_ref" '%s' "$__consumed_count"
}

# --- hs_persist_state ----------------------------------------------------------
# Function:
#   hs_persist_state
# Description:
#   Emits a bash code snippet that, when eval'd in the receiving scope,
#   will recreate the specified local variables with their current values.
#   The emitted code checks if the variable is declared `local` in the receiving
#   scope before assigning to it, to avoid polluting global scope.
#   If the variable already exists and is non-empty in the receiving scope,
#   an error message is printed and the assignment is skipped.
# Arguments:
#   -s <state> - optional; if provided, appends the emitted code to variable
#                definitions found in <state> (bash code snippet).
#   -S <statevar> - optional; if provided, appends the emitted code to variable
#                   definitions found in the variable <statevar>. The variable 
#                   must be empty or uninitialized if -s is also used.
#   $@ - names of local variables to persist.
# Usage examples:
#   # direct eval
#   state=$(hs_persist_state var1 var2)
#   cleanup() {
#       local var1 var2
#       eval "$1"
#       # vars are available here
#   }
hs_persist_state() {
    local __existing_state=""
    local __output_state_var=""
    local __consumed_state_args=0
    _hs_resolve_state_inputs hs_persist_state __existing_state __output_state_var __consumed_state_args "$@" || return $?
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
            echo "[ERROR] hs_persist_state: refusing to persist reserved variable name '$__var_name'." >&2  
            return "$HS_ERR_RESERVED_VAR_NAME"
        fi
        # Detect name collisions if __existing_state is provided
        if [ -n "$__existing_state" ]; then
            # In a time-constrained subshell, declare "$__var_name" as local to capture its value
            # and attempt to restore it from "$__existing_state".
            timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -elc "
                command_not_found_handle() {
                    echo \"[ERROR] hs_persist_state: command '\$1' not found.\" >&2
                    exit 127
                }
                test_collision() {
                    local \"$__var_name\"
                    eval \"$__existing_state\" >/dev/null
                    # Check if the variable pointed to by __var_name has been initialized
                    if ! [ -z \"\${${__var_name}+x}\" ]; then
                        echo \"[ERROR] hs_persist_state: variable '$__var_name' is already defined in the state, with value '\${${__var_name}}'.\" >&2
                        exit 1
                    fi
                }
                test_collision
            " 
            local status=$?
            if [ $status -eq 124 ] || [ $status -eq 127 ] || [ $status -eq 137 ] || [ $status -eq 143 ]; then
                # Status code snippet timed out: 124 (timeout), 137 (killed), 127 (command not found), 143 (sigterm)
                echo "[ERROR] hs_persist_state: prior state is corrupted." >&2
                return $((HS_ERR_CORRUPT_STATE))
            elif [ $status -eq 1 ]; then
                return $((HS_ERR_VAR_NAME_COLLISION))
            elif [ $status -ne 0 ]; then
                echo "[ERROR] hs_persist_state: internal error while checking for variable name collision for '$__var_name'." >&2
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
    if [ -n "$__output_state_var" ]; then
        eval "$__output_state_var=\"\$__output\""
    else
        printf '%s\n' "$__output"
    fi
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
#   -s <state> - optional; if provided, appends the emitted code to variable
#                definitions found in <state> (bash code snippet).
#   -S <statevar> - optional; if provided, appends the emitted code to variable
#                   definitions found in the variable <statevar>. The variable 
#                   must be empty or uninitialized if -s is also used.
#   $@ - names of local variables to destroy.
# Usage examples:
#   mylib_cleanup() {
#       hs_destroystate "$@" mylib_statevar1 mylibstatevar2 
#   }
hs_destroy_state() {
    # Step 1: resolve the input/output state sources using the same -s/-S
    # parsing rules as hs_persist_state. After this call:
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
    local __line=""
    local __state_var=""
    local __state_var_found=false
    local __keep_var=""
    local __keep_state_names=""
    local __state_var_names=""

    # Step 3: validate the destroy list itself before touching the state.
    # Each requested name must be a syntactically valid shell variable name.
    for __var_name in "$@"; do
        if ! [[ "$__var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            echo "[ERROR] hs_destroy_state: invalid variable name '$__var_name'." >&2
            return "$HS_ERR_INVALID_VAR_NAME"
        fi
    done

    # Step 4: scan the existing state snippet for persisted variable names.
    # We intentionally look only for the top-level headers emitted by
    # hs_persist_state:
    #   if local -p VAR >/dev/null 2>&1; then
    # For each discovered variable:
    #   - record it in __state_var_names
    #   - if it is NOT in the destroy list, add it to __keep_state_names
    # We do not splice the blocks directly. We only discover the names here;
    # the actual output state will be rebuilt from surviving variables later.
    while IFS= read -r __line || [[ -n "$__line" ]]; do
        if [[ "$__line" =~ ^if\ local\ -p\ ([a-zA-Z_][a-zA-Z0-9_]*)\ \>/dev/null\ 2\>\&1\;\ then$ ]]; then
            __state_var="${BASH_REMATCH[1]}"
            __state_var_names+="${__state_var}"$'\n'
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
        fi
    done <<< "$__existing_state"

    # Step 5: if we were given a non-empty state string but found no persisted
    # variable headers at all, treat that state as corrupt.
    if [[ -n "$__existing_state" && -z "$__state_var_names" ]]; then
        echo "[ERROR] hs_destroy_state: prior state is corrupted." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi

    # Step 6: every requested variable must actually exist in the incoming
    # state. If a requested name is absent, return HS_ERR_INVALID_VAR_NAME.
    for __var_name in "$@"; do
        __state_var_found=false
        while IFS= read -r __state_var || [[ -n "$__state_var" ]]; do
            if [[ "$__state_var" == "$__var_name" ]]; then
                __state_var_found=true
                break
            fi
        done <<< "$__state_var_names"
        if [[ "$__state_var_found" == false ]]; then
            echo "[ERROR] hs_destroy_state: variable '$__var_name' is not defined in the state." >&2
            return "$HS_ERR_VAR_NAME_NOT_IN_STATE"
        fi
    done

    # Step 7: rebuild the state from scratch using only the survivor names.
    # Instead of editing the text blocks in place, run a fresh Bash subprocess
    # that:
    #   1. defines the minimal helpers needed (_hs_resolve_state_inputs and
    #      hs_persist_state plus their error-code constants),
    #   2. declares every survivor variable local,
    #   3. evals the incoming state to restore those locals,
    #   4. calls the stdout form of hs_persist_state on the survivor list.
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
            '"$(declare -f _hs_resolve_state_inputs)"'
            '"$(declare -f hs_persist_state)"'
            _hs_destroy_state_rebuild() {
                local __rebuild_state=$1
                shift
                local __name
                for __name in "$@"; do
                    local "$__name"
                done
                eval "$__rebuild_state" >/dev/null
                hs_persist_state "$@"
            }
            _hs_destroy_state_rebuild "$@"
        ' bash "$__existing_state" "${__keep_state_args[@]}")
        local __status=$?
        # Step 8: map rebuild failures to the same "corrupt prior state"
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

    # Step 9: emit the rebuilt state using the same stdout / -S convention as
    # hs_persist_state.
    if [ -n "$__output_state_var" ]; then
        printf -v "$__output_state_var" '%s' "$__output"
    else
        printf '%s\n' "$__output"
    fi
}
# --- hs_read_persisted_state --------------------------------------------------------
# Function: 
#   hs_read_persisted_state
# Description: 
#   Emits the state string produced by `hs_persist_state` without evaluating it.
#   The state is passed by variable name and accessed via a nameref, so callers
#   do not pass the snippet by value. This function still only returns the
#   stored code snippet; callers should `eval "$(hs_read_persisted_state state)"`
#   or simply `eval "$state"` to recreate variables in the caller scope.
#   Can be called several times to extract distinct variables.
#   The referenced state variable contains a bash code snippet that assigns
#   values to existing local and empty variables in the current scope.
# Arguments:
#   $1 - name of the variable holding the state string produced by `hs_persist_state`
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
    local -n state_string="$1"
    printf '%s' "$state_string"
}

# --- Utility functions --------------------------------------------------------
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

# Initialize logging when the script is sourced
hs_setup_output_to_stdout

# Note: Remember to call hs_cleanup at the end of your main script to clean up resources.
