#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Function: hs_persist_state
# Description: Reads a list of local variable names as arguments and prints to stdout properly
#         escaped shell commands to recreate those variables with their current values, but
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
                # ensure the local is declared and empty before restoring it.
                printf 'if ! local -p %s >/dev/null 2>&1; then\n  printf "[ERROR] cleanup must declare local %s before restoring state\\n" >&2\n  false\nelif [ -n "${%s+x}" ] && [ -n "${%s}" ]; then\n  printf "[ERROR] local %s already set in cleanup; refusing to overwrite\\n" >&2\n  false\nelse\n  %s=%q\nfi\n' \
                    "$var_name" "$var_name" "$var_name" "$var_name" "$var_name" "$var_name" "$var_value"
        fi
    done
}

# Function: hs_read_persisted_state
# Description: Emits the state string produced by `hs_persist_state` without
# evaluating it. This avoids executing the state inside this function's scope
# (which would prevent assignments to `local` variables declared in the
# calling function). Callers should `eval "$(hs_read_persisted_state "$state")"`
# or simply `eval "$state"` to recreate variables in the caller scope.
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
