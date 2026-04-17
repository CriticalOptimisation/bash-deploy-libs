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
readonly HS_ERR_INVALID_ARGUMENT_TYPE=9

# --- hs_persist_state_as_code ----------------------------------------------------------
# Function:
#   hs_persist_state_as_code [options] [--] [state_variable ...]
# Description:
#   Produces an opaque state object that preserves the current values of the
#   specified local variables for later restoration via
#   `hs_read_persisted_state`.
#   The current implementation stores that state as guarded Bash code, but
#   callers should treat the resulting value as internal transport data rather
#   than as a public snippet format.
#   Restoration only initializes matching `local` variables in the receiving
#   scope and skips variables that are already non-empty there.
# Options:
#   -S <state> - pass the state object by name, mandatory.
#   Other options are ignored up to the last --, so this function is usually able
#   to directly process its caller's argument list, future-proofing it against
#   new hs_persist_state_as_code options.
#   -- - marks the end of options and the beginning of the list of variable names.
# Arguments:
#   $@ - names of local variables to persist. Without `--`, the trailing
#        arguments that are valid Bash identifiers are treated as the variable list.
#        Note that the value associated with the last given option will be mistaken
#        for a variable unless `--` is used.
# Errors:
#   - Rejects a missing `-S` option.
#   - Rejects an invalid variable name.
#   - Rejects collisions with variables already present in the prior state.
# Usage examples:
#   local state
#   init() {
#       local var1 var2
#       hs_persist_state_as_code "$@" -- var1 var2
#   }
#
#   init -S state
hs_persist_state_as_code() {
    local -a __remaining_args=()
    local -A __processed_args=()
    _hs_resolve_state_inputs hs_persist_state_as_code __remaining_args S: __processed_args "$@" || return $?
    local __output_state_var="${__processed_args[state]}"
    local __existing_state="${!__output_state_var-}"
    local -a __persist_var_args=()
    read -r -a __persist_var_args <<< "${__processed_args[vars]-}"
    # Initialize output state string
    local __output=""
    if [ -n "$__existing_state" ]; then
        __output="$__existing_state"
    fi
    local __var_name
    if [[ -n "$__existing_state" && ${#__persist_var_args[@]} -gt 0 ]]; then
        timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
            command_not_found_handle() {
                echo "[ERROR] hs_persist_state_as_code: command '"'"'$1'"'"' not found." >&2
                exit 127
            }
            _hs_detect_state_collisions() {
                local __state=$1
                shift
                local __name
                local -a __collisions=()

                # Declare every candidate as a local shell variable, but leave
                # it uninitialized so a later [[ -v name ]] test only becomes
                # true for variables that were actually restored from state.
                for __name in "$@"; do
                    local "$__name"
                done

                eval "$__state" >/dev/null || return $?

                for __name in "$@"; do
                    if [ "${!__name+x}" ]; then
                        __collisions+=("$__name")
                    fi
                done

                if (( ${#__collisions[@]} > 0 )); then
                    echo "[ERROR] hs_persist_state_as_code: variables already defined in the state: ${__collisions[*]}." >&2
                    return 1
                fi
            }
            _hs_detect_state_collisions "$@"
        ' bash "$__existing_state" "${__persist_var_args[@]}"
        local status=$?
        if [ $status -eq 124 ] || [ $status -eq 127 ] || [ $status -eq 137 ] || [ $status -eq 143 ]; then
            echo "[ERROR] hs_persist_state_as_code: prior state is corrupted." >&2
            return $((HS_ERR_CORRUPT_STATE))
        elif [ $status -eq 1 ]; then
            return $((HS_ERR_VAR_NAME_COLLISION))
        elif [ $status -ne 0 ]; then
            echo "[ERROR] hs_persist_state_as_code: internal error while checking for variable name collisions." >&2
            return $((HS_ERR_CORRUPT_STATE))
        fi
    fi
    for __var_name in "${__persist_var_args[@]}"; do
        # Check that the value of __var_name is neither "__var_name" nor "__existing_state"
        if [ "$__var_name" = "__var_name" ] || [ "$__var_name" = "__existing_state" ] || [ "$__var_name" = "__output_state_var" ] || [ "$__var_name" = "__output" ]; then
            echo "[ERROR] hs_persist_state_as_code: refusing to persist reserved variable name '$__var_name'." >&2  
            return "$HS_ERR_RESERVED_VAR_NAME"
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
#   hs_destroy_state [options] [--] [state_variable ...]
# Description:
#   Removes the specified local variables from an opaque state object.
#   In a cleanup function, this allows the same state variable to be reused by
#   a later init call without triggering name-collision errors.
# Options:
#   -S <state> - pass the state object by name, mandatory.
#   Other options are ignored up to the last --, so this function is usually able
#   to directly process its caller's argument list, future-proofing it against
#   new hs_destroy_state options.
#   -- - marks the end of options and the beginning of the list of variable names.
# Arguments:
#   $@ - names of local variables to destroy. Without `--`, the trailing
#        arguments that are valid Bash identifiers are treated as the variable list.
#        Note that the value associated with the last given option will be mistaken
#        for a variable unless `--` is used.
# Errors:
#   - Rejects a missing `-S` option.
#   - Rejects an invalid variable name.
#   - Rejects destroy requests for variables not present in the state object.
# Usage examples:
#   cleanup_function() {
#       hs_destroy_state "$@" -- mylib_statevar1 mylib_statevar2
#   }
hs_destroy_state() {
    # Step 1: resolve the input/output state sources using the same -S-only
    # parsing rules as hs_persist_state_as_code. After this call:
    #   - __existing_state contains the input state snippet to transform
    #   - __output_state_var names the destination variable, if -S was used
    #   - __consumed_state_args tells us how many option arguments to discard
    #     before "$@" contains only variable names to destroy.
    local -a __remaining_args=()
    local -A __processed_args=()
    _hs_resolve_state_inputs hs_destroy_state __remaining_args S: __processed_args "$@" || return $?
    local __output_state_var="${__processed_args[state]}"
    local __existing_state="${!__output_state_var-}"
    local -a __destroy_var_args=()
    read -r -a __destroy_var_args <<< "${__processed_args[vars]-}"

    # Step 2: set up working variables.
    # __state_var_names will contain every variable name found in the incoming
    # persisted state. __state_var_set mirrors that list as an associative set
    # so destroy-name lookups and removals stay in Bash builtins instead of
    # nested shell loops.
    local __output=""
    local __var_name
    local __state_var=""
    local -a __state_var_names=()
    local -A __state_var_set=()

    # Step 3: scan the existing state snippet for persisted variable names.
    # We intentionally look only for the top-level headers emitted by
    # hs_persist_state_as_code. We do not splice the blocks directly. We only
    # discover the names here; the actual output state will be rebuilt from
    # surviving variables later.
    _hs_extract_persisted_state_var_names hs_destroy_state "$__existing_state" __state_var_names || return $?
    for __state_var in "${__state_var_names[@]}"; do
        __state_var_set["$__state_var"]=1
    done

    # Step 4: every requested variable must actually exist in the incoming
    # state. If it does, remove it from the survivor set immediately so the
    # final key list is exactly the set of variables to keep.
    for __var_name in "${__destroy_var_args[@]}"; do
        if [[ -z "${__state_var_set["$__var_name"]-}" ]]; then
            echo "[ERROR] hs_destroy_state: variable '$__var_name' is not defined in the state." >&2
            return "$HS_ERR_VAR_NAME_NOT_IN_STATE"
        fi
        unset '__state_var_set[$__var_name]'
    done

    # Step 5: rebuild the state from scratch using only the survivor names.
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
    local -a __keep_state_args=("${!__state_var_set[@]}")
    if (( ${#__keep_state_args[@]} > 0 )); then

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
        # Step 6: map rebuild failures to the same "corrupt prior state"
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

    # Step 7: write the rebuilt state back into the named state variable.
    printf -v "$__output_state_var" '%s' "$__output"
}
# --- hs_read_persisted_state --------------------------------------------------------
# Function: 
#   hs_read_persisted_state [options] [--] [state_variable ...]
# Description: 
#   Restores values from the opaque state object produced by
#   `hs_persist_state_as_code`.
#   For convenience, callers may pass either `state` or `-S state`.
#   When explicit variable names are provided, those named locals are restored
#   directly into the current caller scope.
#   Without an explicit list, the function emits a safe, locally generated probe
#   snippet that reenters `hs_read_persisted_state` with the names of matching
#   empty locals found in the immediate caller scope.
# Options:
#   -q - suppresses the warning that is normally emitted when a requested
#        state variable is not present in the state object.
#   -S <state> - pass the state object by name, mandatory.
#   Other options are ignored up to the last --, so this function is usually able
#   to directly process its caller's argument list, future-prooving it against
#   new hs_read_persisted_state options.
#   -- - marks the end of options and the beginning of the list of variable names.
# Arguments:
#   $@ - names of local variables to restore. Without `--`, the trailing
#        arguments that are valid Bash identifiers are treated as the variable list.
#        Note that the detached value associated with the last given option will be mistaken
#        for a variable unless that option is known or `--` is used.
# Errors:
#   - Rejects a missing `-S` option.
#   - Rejects an invalid variable name.
#   - Rejects a state variable that is missing, unset, or empty.
# Usage examples:
#   cleanup() {
#       local state_var="$1"
#       local temp_file resource_id
#       hs_read_persisted_state -S "$state_var" -- temp_file resource_id
#   }
#   # Better: keeps -S convention for cleanup().
#   cleanup() {
#       local temp_file resource_id
#       hs_read_persisted_state -q "$@" -- temp_file resource_id
#   }
hs_read_persisted_state() {
    # Step 1: normalize the convenience form `hs_read_persisted_state state`
    # into the regular `-S state` form, then delegate all option parsing to
    # _hs_resolve_state_inputs.
    if [ $# -eq 0 ]; then
        echo "[ERROR] hs_read_persisted_state: missing required state variable name." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi

    if [[ "${1-}" != -* ]]; then
        set -- -S "$@"
    fi
    # Step 2: resolve the named state variable and capture its current payload.
    # The helper validates names, enforces the presence of -S, and returns:
    #   - __output_state_var: the caller-visible variable name holding that state
    #   - __processed_args[quiet]: whether -q was provided
    #   - __processed_args[vars]: the validated requested-variable list
    local -a __remaining_args=()
    local -A __processed_args=()
    _hs_resolve_state_inputs hs_read_persisted_state __remaining_args qS: __processed_args "$@" || return $?
    local __quiet="${__processed_args[quiet]}"
    local __output_state_var="${__processed_args[state]}"
    local __existing_state="${!__output_state_var-}"
    local __has_separator="${__processed_args[separator]-}"
    local -a __requested_var_args=()
    read -r -a __requested_var_args <<< "${__processed_args[vars]-}"

    if [ -z "$__existing_state" ]; then
        echo "[ERROR] hs_read_persisted_state: state variable '$__output_state_var' is not set or is empty." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi

    # Step 3: if the caller listed variable names after the state input, restore
    # only those variables directly into the caller scope. This is the explicit
    # selective-restore API.
    if [ ${#__requested_var_args[@]} -gt 0 ]; then
        local __requested_var
        local __restored_payload=""
        local __restore_status=0
        # Evaluate the persisted state in a single short-lived Bash subprocess,
        # restore all requested variables there, and return one
        # associative-array initializer of restored string values. Missing
        # variables are reported directly on stderr from that subprocess.
        __restored_payload=$(timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
            _hs_read_requested_state_vars() {
                local __state=$1
                local __quiet_mode=$2
                shift
                shift
                local __requested_var
                local __restored_entries=""

                for __requested_var in "$@"; do
                    local "$__requested_var"
                done

                eval "$__state" >/dev/null 2>&1 || return $?

                for __requested_var in "$@"; do
                    if [ "${!__requested_var+x}" ]; then
                        printf -v __restored_entries "%s[%q]=%q " "$__restored_entries" "$__requested_var" "${!__requested_var}"
                    else
                        if [ "$__quiet_mode" = false ]; then
                            printf "[WARNING] hs_read_persisted_state: variable '"'"'%s'"'"' is not defined in the state.\n" "$__requested_var" >&2
                        fi
                    fi
                done

                printf "%s" "$__restored_entries"
            }
            _hs_read_requested_state_vars "$@"
        ' bash "$__existing_state" "$__quiet" "${__requested_var_args[@]}")
        __restore_status=$?

        if [ $__restore_status -eq 124 ] || [ $__restore_status -eq 127 ] || [ $__restore_status -eq 137 ] || [ $__restore_status -eq 143 ]; then
            echo "[ERROR] hs_read_persisted_state: prior state is corrupted." >&2
            return "$HS_ERR_CORRUPT_STATE"
        elif [ $__restore_status -ne 0 ]; then
            echo "[ERROR] hs_read_persisted_state: internal error while restoring requested variables." >&2
            return "$HS_ERR_CORRUPT_STATE"
        fi

        local -A __restored_map=()
        if [[ -n "$__restored_payload" ]]; then
            eval "__restored_map=($__restored_payload)"
        fi

        for __requested_var in "${!__restored_map[@]}"; do
            local -n __requested_var_ref="$__requested_var"
            __requested_var_ref="${__restored_map[$__requested_var]}"
        done
        return 0
    fi

    # Step 4: if the caller used an explicit `--` but provided no variable
    # names after it, do not emit the auto-probe snippet. This lets callers
    # disable the stdout/eval path intentionally.
    if [[ -n "$__has_separator" ]]; then
        return 0
    fi

    # Step 5: otherwise, generate a generic local-scope probe snippet instead
    # of returning the raw persisted code. The snippet inspects the current
    # function's locals with `local -p`, selects unset scalar locals, and
    # reenters hs_read_persisted_state with -q so unrelated locals stay quiet.
    IFS= read -r -d '' __probe_snippet <<EOF || true
hs_read_persisted_state -q -S $(printf '%q' "$__output_state_var") -- \$(
  local -p | while IFS= read -r __hs_local_decl; do
    [[ "\$__hs_local_decl" == *=* ]] && continue
    [[ "\$__hs_local_decl" =~ ^declare\ -[^[:space:]]*[aA] ]] && continue
    __hs_local_name=\${__hs_local_decl##* }
    [[ "\$__hs_local_name" == __hs_* ]] && continue
    printf '%s ' "\$__hs_local_name"
  done
) >/dev/null
EOF
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
#   $2 - name of the array variable that will receive the unprocessed arguments; must be a valid Bash name
#   $3 - getopts format string of accepted parameters; e.g. qS::
#   $4 - name of the associative array variable that will receive the processed arguments; must be a valid Bash name
#   $5 - first forwarded argument option
#   $6... - additional forwarded arguments; if `--` is present, its last
#           occurrence marks the start of the explicit variable-name list
# Returns:
#   0 on success.
#   `HS_ERR_MISSING_ARGUMENT` if fewer than 6 arguments are provided.
#   `HS_ERR_INVALID_ARGUMENT_TYPE` if the output containers do not have the
#   expected array types.
#   `HS_ERR_STATE_VAR_UNINITIALIZED` if no `-S <statevar>` option is provided.
#   `HS_ERR_INVALID_VAR_NAME` if `-S` is followed by an invalid variable name.
# Usage:
#   local existing_state="" output_state_var="" consumed_state_args=0
#   _hs_resolve_state_inputs my_helper existing_state output_state_var consumed_state_args "$@" || return $?
_hs_resolve_state_inputs() {
    if [ $# -lt 4 ]; then
        echo "[ERROR] $1: missing required arguments; expected at least 4 parameters." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi
    local __arg
    for __arg in "$1" "$2" "$4"; do
        if ! _hs_is_valid_variable_name "$__arg"; then
            echo "[ERROR] $1: invalid variable name '$__arg'." >&2
            return "$HS_ERR_INVALID_VAR_NAME"
        fi
    done
    local __caller_name=$1
    local -n __remaining_args_ref=$2
    local __options=$3
    local -n __processed_args_ref=$4
    shift 4

    # Validate the types of passed arrays using ${...@a}
    if ! _hs_is_array __remaining_args_ref; then
        echo "[ERROR] ${__caller_name}: '${!__remaining_args_ref}' must name an indexed array variable." >&2
        return "$HS_ERR_INVALID_ARGUMENT_TYPE"
    fi
    if ! _hs_is_array -A __processed_args_ref; then
        echo "[ERROR] ${__caller_name}: '${!__processed_args_ref}' must name an associative array variable." >&2
        return "$HS_ERR_INVALID_ARGUMENT_TYPE"
    fi

    
    # Initialize processed options
    __processed_args_ref=(["quiet"]=false)

    # Process options
    # Increments OPTIND scanning for known options.
    __remaining_args_ref=()
    local -i OPTIND=1
    local opt
    local -i index
    
    # Force a colon in front of $__options to record unknown options in $OPTARG
    while (( "$#" >= "$OPTIND" )); do
        index=${OPTIND}
        if getopts ":$__options" opt; then
            # Returns OK if known or unknown option -X [val]
            # value is assigned to $OPTARG for known options
            # value can be attached -Svarname or detached -S varname
            case "$opt" in
                \?)
                    # Unknown option
                    __remaining_args_ref+=("-$OPTARG")
                    ;;
                S)
                    if ! _hs_is_valid_variable_name "$OPTARG"; then
                        echo "[ERROR] ${__caller_name}: invalid variable name '${OPTARG}'." >&2
                        return "$HS_ERR_INVALID_VAR_NAME"
                    fi
                    __processed_args_ref["state"]="$OPTARG"
                    ;;
                q)
                    __processed_args_ref["quiet"]=true
                    ;;
                :)
                    # Only triggered by -S in the last position since getopts accepts
                    # -q or -- as the value of -S if it encounters ... -S -q or ... -S -- ...
                    echo "[ERROR] ${__caller_name}: missing required parameter to option -${OPTARG}." >&2
                    return "$HS_ERR_MISSING_ARGUMENT"
                    ;;
            esac
        elif (( "$index" == "$OPTIND" )); then
            # It was a word (parameter to some unknown option)
            __remaining_args_ref+=("${!OPTIND}")
            OPTIND=$(( OPTIND + 1 ))
        else
            # Hit --. Stop decoding options.
            __processed_args_ref["separator"]=true
            while (( "$#" >= "$OPTIND" )); do 
                if ! _hs_is_valid_variable_name "${!OPTIND}"; then
                    echo "[ERROR] ${__caller_name}: invalid variable name '${!OPTIND}'." >&2
                    return "$HS_ERR_INVALID_VAR_NAME"
                fi
                printf -v __processed_args_ref["vars"] "%s %s" "${!OPTIND}" "${__processed_args_ref['vars']}"
                OPTIND=$(( OPTIND + 1 ))
            done
        fi
    done

    # Pull variable names from the end
    : "${__processed_args_ref["vars"]:=}"
    if [[ -z "${__processed_args_ref[separator]-}" ]]; then
        while (( ${#__remaining_args_ref[@]} > 0 )) && _hs_is_valid_variable_name "${__remaining_args_ref[-1]}"; do
            printf -v __processed_args_ref["vars"] "%s %s" "${__remaining_args_ref[-1]}" "${__processed_args_ref['vars']}"
            unset "__remaining_args_ref[-1]"
        done

        local __remaining_arg
        for __remaining_arg in "${__remaining_args_ref[@]}"; do
            if [[ "$__remaining_arg" != -* ]]; then
                echo "[ERROR] ${__caller_name}: invalid variable name '${__remaining_arg}'." >&2
                return "$HS_ERR_INVALID_VAR_NAME"
            fi
        done
    fi
    
    if [[ -z "${__processed_args_ref[state]-}" ]]; then
        echo "[ERROR] ${__caller_name}: state variable is uninitialized; missing required -S <statevar> option." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi
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

_hs_is_array() {
    local arraytypes="a"
    if [[ "$1" == "-A" ]]; then
        arraytypes="A"
        shift
    fi
    local -n vname=$1 
    local attrs
    attrs=${vname@a}
    [[ "$attrs" == *[$arraytypes]* ]]
}
