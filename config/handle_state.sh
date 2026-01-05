#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

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
hs_setup_output_to_stdout() {
    # Test if already set up
    if hs_get_pid_of_subshell >/dev/null 2>&1; then
        hs_echo "[WARN] hs_setup_output_to_stdout: already set up; skipping." >&2
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
    # Parameters:
    #   None
    printf -v _hs_qtoken '%q' "$_hs_fifo_kill_token"
    eval "hs_cleanup_output() {
        if hs_echo $_hs_qtoken ; then
            wait $_hs_fifo_reader_pid 2>/dev/null
            hs_cleanup_output() { :; }
        fi
        return 0
    }"
}

# Function:
#   hs_echo
# Description:
#   Writes messages to the logging FIFO for display in the main script's stdout.
#   Specifically designed to work inside subshells called via `$(...)`.
# Arguments:
#   $* - echo options -neE or message parts to echo
hs_echo() {
    # Mimic Bash echo argument concatenation behavior.
    # Here IFS acts on "$*" expansion to insert spaces between arguments.
    IFS=" " echo "$*" >&"${_hs_fifo_fd}"
}

#         Commands to recreate those variables with their current values, but
#         **without creating or overwriting global environment variables**. The generated code
#         will only assign to a variable if it is already declared *local* in the receiving
#         scope (i.e., the cleanup function should `local varname` before `eval`ing the state).
#         Does not persist state in files.
#         It is the caller's responsibility to capture the output and pass it to the cleanup function,
#         catching errors as needed (e.g. with `trap`) to ensure the cleanup function is called.
#
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
hs_persist_state() {
    local var_name
    for var_name in "$@"; do
        # Check if the variable exists in the caller (local or global). We avoid
        # using `local -p` here because that only inspects locals of this
        # function, not the caller's scope. If the variable exists, capture its
        # value and emit a guarded assignment that will only set it in the
        # receiving scope if that scope has declared it `local`.
        if [ "${!var_name+x}" ]; then
            # Get the value of the variable
            local var_value
            eval "var_value=\"\${$var_name}\"" || eval "var_value=\"\$$var_name\""
            # Emit a snippet that, when eval'd in the receiving scope, will
            # restore the existing, empty local variables from the saved state.
            printf "
if local -p %s >/dev/null 2>&1; then
  if [ -n \"\${%s+x}\" ] && [ -n \"\${%s}\" ]; then
    printf \"[ERROR] local %s already defined; refusing to overwrite\\n\" >&2
    return 1
  else
    %s=%q
  fi
fi
" "$var_name" "$var_name" "$var_name" "$var_name" "$var_name" "$var_value"
        fi
    done
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


