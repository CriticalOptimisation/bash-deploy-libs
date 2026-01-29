#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__HANDLE_STATE_SH_INCLUDED:-} ]] && __HANDLE_STATE_SH_INCLUDED=1 || return 0

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
    while [ $# -gt 0 ]; do
        case "$1" in
            -s)
                shift
                __existing_state="$1"
                shift
                ;;
            -S)
                shift
                __output_state_var="$1"
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    # If __output_stat_var is set, we have to check if __existing_state is set too,
    # and enforce that ${!__output_state_var} is uninitialized or empty to ensure
    # that we are not dealing with multiple prior state strings.
    if [ -n "$__output_state_var" ] && [ -n "$__existing_state" ]; then
        echo "[ERROR] hs_persist_state: cannot pass prior state using both -s and -S options simultaneously." >&2
        return "$HS_ERR_MULTIPLE_STATE_INPUTS"
    fi
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
        # In a subshell, declare "$__var_name" as local to capture its value and
        # attempt to restore it from "$__existing_state".
        (
            local "$__var_name"
            if [ -n "$__existing_state" ]; then
                eval "$__existing_state" >/dev/null 2>&1
            fi
            # Check if the variable pointed to by __var_name has been initialized
            if ! [ -z "${!__var_name+x}" ]; then
                echo "[ERROR] hs_persist_state: variable '$__var_name' is already defined in the state, with value '${!__var_name}'." >&2
                return 1
            fi
        ) || return "$HS_ERR_VAR_NAME_COLLISION"
        # Check if the variable exists in the caller (local or global). We avoid
        # using `local -p` here because that only inspects locals of this
        # function, not the caller's scope. If the variable exists, capture its
        # value and emit a guarded assignment that will only set it in the
        # receiving scope if that scope has declared it `local`.
        if [ "${!__var_name+x}" ]; then
            # Get the value of the variable
            local var_value
            eval "var_value=\"\${$__var_name}\"" || eval "var_value=\"\$$__var_name\""
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

# --- hs_read_persisted_state --------------------------------------------------------
# Function: 
#   hs_read_persisted_state
# Description: 
#   Emits the state string produced by `hs_persist_state` without
#   evaluating it. This avoids executing the state inside this function's scope
#   (which would prevent assignments to `local` variables declared in the
#   calling function). Callers should `eval "$(hs_read_persisted_state "$state")"`
#   or simply `eval "$state"` to recreate variables in the caller scope.
#   Can be called several times to extract distinct variables.
#   "$state" is a bash code snippet that assigns values to existing local and empty
#   variables in the current scope.
# Arguments:
#   $1 - state string produced by `hs_persist_state`
# Usage examples:
#   # direct eval
#   cleanup() {
#       local temp_file resource_id
#       eval "$1"
#       # vars are available here
#   }
#
#   # helper wrapper form (prints state; caller evals it in its own scope)
#   cleanup() {
#       local state="$1"
#       local temp_file resource_id
#       eval "$(hs_read_persisted_state \"$state\")"
#   }
hs_read_persisted_state() {
    local state_string="$1"
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


