#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__HANDLE_STATE_SH_INCLUDED:-} ]] && __HANDLE_STATE_SH_INCLUDED=1 || return 0

# Source command guard for secure external command usage
# shellcheck source=command_guard.sh
source "${BASH_SOURCE%/*}/command_guard.sh"

# Library usage:
#   In an initialization function, call hs_persist_state_as_code with the names of local variables
#   that need to be preserved for later use in a cleanup function.
# Example:
#   init_function() {
#       local temp_file="/tmp/some_temp_file"
#       local resource_id="resource_123"
#       hs_persist_state_as_code "$@" -- temp_file resource_id
#   }
#   cleanup() {
#       local temp_file
#       local resource_id
#       hs_read_persisted_state "$@" -- temp_file resource_id
#       rm -f "$temp_file"
#       printf 'Cleaned up resource: %s\n' "$resource_id"
#       hs_destroy_state "$@" -- temp_file resource_id
#   }
#
# Upper level usage:
#   local _state=""
#   init_function -S _state
#   cleanup -S _state

guard timeout
guard cksum

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
readonly HS_ERR_UNKNOWN_VAR_NAME=10
readonly HS_ERR_VAR_ALREADY_SET=11
readonly HS_ERR_NAMEREF_TARGET_NOT_PERSISTED=12

# --- hs_persist_state_as_code ----------------------------------------------------------
# Function:
#   hs_persist_state_as_code [options] [--] [state_variable ...]
# Description:
#   Appends the current values of the specified local variables to the opaque
#   state object held in the variable named by -S, for later consumption via
#   `hs_read_persisted_state` in the receiving scope.
#   The state format is internal; treat the named variable as an opaque token
#   and do not inspect or modify its value directly.
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
#   - `HS_ERR_STATE_VAR_UNINITIALIZED` if `-S <statevar>` is missing.
#   - `HS_ERR_INVALID_VAR_NAME` if the state variable name or a requested
#     persisted variable name is not a valid Bash identifier.
#   - `HS_ERR_RESERVED_VAR_NAME` if a requested persisted variable name is one
#     of the helper's reserved internal names.
#   - `HS_ERR_VAR_NAME_COLLISION` if one or more requested variable names are
#     already defined in the prior state object.
#   - `HS_ERR_CORRUPT_STATE` if the prior state object cannot be evaluated
#     safely during collision checking.
#   - `HS_ERR_UNKNOWN_VAR_NAME` if a requested variable name is not declared
#     in the caller's scope (catches typos and function names).
# Usage examples:
#   local state_var
#   init() {
#       local var1 var2
#       hs_persist_state_as_code "$@" -- var1 var2
#   }
#
#   init -S state_var
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
        # shellcheck disable=SC2016
        timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
            # Normalize unknown commands reached via eval into a corrupt-state failure.
            command_not_found_handle() {
                echo "[ERROR] hs_persist_state_as_code: command '"'"'$1'"'"' not found." >&2
                exit 127
            }
            _hs_detect_state_collisions() {
                local __hs_state=$1
                shift

                # Declare every candidate as an unset local scalar, then detect
                # whether eval changed it into a set variable or a nonscalar.
                local "$@"

                eval "$__hs_state" >/dev/null || return $?

                while [ $# -gt 0 ]; do
                    # A touched variable either became set as a scalar
                    # (`local -p name` prints an assignment) or changed type to
                    # an array. If `local -p` itself fails here, treat that as
                    # corruption propagated from eval.
                    if [[ "$(local -p "$1" 2>/dev/null)" == *=* ]] || [[ ${!1@a} == *[aA]* ]]; then
                        echo "[ERROR] hs_persist_state_as_code: variable already defined in the state: $1." >&2
                        return 1
                    fi
                    local -p "$1" >/dev/null 2>&1 || return $?
                    shift
                done
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
        # Fail fast if the name is not declared as a variable in the dynamic scope
        # (catches typos and misuse of function names).
        if ! declare -p "$__var_name" >/dev/null 2>&1; then
            if declare -f "$__var_name" >/dev/null 2>&1; then
                echo "[ERROR] hs_persist_state_as_code: '$__var_name' is a function, not a variable." >&2
                return "$HS_ERR_UNKNOWN_VAR_NAME"
            fi
            echo "[ERROR] hs_persist_state_as_code: '$__var_name' is not declared in scope." >&2
            return "$HS_ERR_UNKNOWN_VAR_NAME"
        fi
        # The variable is declared. If it is set, persist it; if unset, skip
        # silently — an unset local is a legitimate intentional omission.
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

# --- hs_persist_state ----------------------------------------------------------
# Function:
#   hs_persist_state [options] [--] [state_variable ...]
# Description:
#   Appends the current values of the specified local variables to an HS2-format
#   opaque state object held in the variable named by -S. Supports scalars,
#   indexed arrays, associative arrays, and namerefs (when the nameref target is
#   also being persisted or is already in the state).
# Options:
#   -S <state> - pass the state object by name, mandatory.
#   -- - marks the end of options and the beginning of the list of variable names.
# Errors:
#   See hs_persist_state_as_code for the full error code list; additionally:
#   - `HS_ERR_NAMEREF_TARGET_NOT_PERSISTED` if a nameref's target is not being
#     persisted in the same call and is not already present in the prior state.
hs_persist_state() {
    local -a __hsp_remaining=()
    local -A __hsp_processed=()
    _hs_resolve_state_inputs hs_persist_state __hsp_remaining S: __hsp_processed "$@" || return $?
    local __hsp_out_var="${__hsp_processed[state]}"
    local __hsp_existing="${!__hsp_out_var-}"
    local -a __hsp_vars=()
    read -r -a __hsp_vars <<< "${__hsp_processed[vars]-}"

    # Parse existing state (must be empty or HS2).
    local __hsp_existing_payload=""
    local -a __hsp_existing_recs=()
    local -A __hsp_existing_names=()
    if [[ -n "$__hsp_existing" ]]; then
        if [[ "$__hsp_existing" != HS2:* ]]; then
            echo "[ERROR] hs_persist_state: existing state is not in HS2 format." >&2
            return "$HS_ERR_CORRUPT_STATE"
        fi
        _hs_hs2_parse hs_persist_state "$__hsp_existing" __hsp_existing_recs || return $?
        local __hsp_tmp="${__hsp_existing#HS2:}"
        __hsp_existing_payload="${__hsp_tmp#*:}"
        local __hsp_er
        for __hsp_er in "${__hsp_existing_recs[@]}"; do
            __hsp_existing_names["$(_hs_hs2_record_name "$__hsp_er")"]=1
        done
    fi

    # Reserved names that must not be persisted.
    local -A __hsp_reserved=(
        [__hsp_remaining]=1 [__hsp_processed]=1 [__hsp_out_var]=1
        [__hsp_existing]=1 [__hsp_vars]=1 [__hsp_existing_payload]=1
        [__hsp_existing_recs]=1 [__hsp_existing_names]=1 [__hsp_reserved]=1
        [__hsp_non_namerefs]=1 [__hsp_namerefs]=1 [__hsp_this_call]=1
        [__hsp_var]=1 [__hsp_decl]=1 [__hsp_flags]=1 [__hsp_target]=1
        [__hsp_er]=1 [__hsp_tmp]=1
    )

    # Phase 1: validate all names; separate non-namerefs from namerefs.
    local -a __hsp_non_namerefs=()
    local -a __hsp_namerefs=()
    local -A __hsp_this_call=()   # name -> "nameref" or "1"
    local __hsp_var __hsp_decl __hsp_flags
    for __hsp_var in "${__hsp_vars[@]}"; do
        if [[ -n "${__hsp_reserved[$__hsp_var]-}" ]]; then
            echo "[ERROR] hs_persist_state: refusing to persist reserved variable name '$__hsp_var'." >&2
            return "$HS_ERR_RESERVED_VAR_NAME"
        fi
        if [[ -n "${__hsp_existing_names[$__hsp_var]-}" ]]; then
            echo "[ERROR] hs_persist_state: variable '$__hsp_var' already exists in the state." >&2
            return "$HS_ERR_VAR_NAME_COLLISION"
        fi
        if ! __hsp_decl=$(declare -p "$__hsp_var" 2>/dev/null); then
            if declare -f "$__hsp_var" >/dev/null 2>&1; then
                echo "[ERROR] hs_persist_state: '$__hsp_var' is a function, not a variable." >&2
            else
                echo "[ERROR] hs_persist_state: '$__hsp_var' is not declared in scope." >&2
            fi
            return "$HS_ERR_UNKNOWN_VAR_NAME"
        fi
        __hsp_flags="${__hsp_decl#declare }"
        __hsp_flags="${__hsp_flags%% *}"
        if [[ "$__hsp_flags" == *n* ]]; then
            __hsp_this_call["$__hsp_var"]=nameref
        else
            __hsp_non_namerefs+=("$(_hs_strip_export "$__hsp_decl")")
            __hsp_this_call["$__hsp_var"]=1
        fi
    done

    # Phase 2: validate nameref targets and build nameref records (after targets).
    local __hsp_target
    for __hsp_var in "${__hsp_vars[@]}"; do
        [[ "${__hsp_this_call[$__hsp_var]-}" == nameref ]] || continue
        __hsp_decl=$(declare -p "$__hsp_var" 2>/dev/null)
        # Extract target: declare -n name="target" → value part between quotes.
        __hsp_target="${__hsp_decl#*\"}"
        __hsp_target="${__hsp_target%\"}"
        if [[ -z "${__hsp_existing_names[$__hsp_target]-}" && \
              -z "${__hsp_this_call[$__hsp_target]-}" ]]; then
            echo "[ERROR] hs_persist_state: nameref '$__hsp_var' target '$__hsp_target' is not being persisted." >&2
            return "$HS_ERR_NAMEREF_TARGET_NOT_PERSISTED"
        fi
        __hsp_namerefs+=("$(_hs_strip_export "$__hsp_decl")")
    done

    # Build HS2 state: existing payload + non-nameref records + nameref records.
    _hs_hs2_build "$__hsp_out_var" "$__hsp_existing_payload" \
        "${__hsp_non_namerefs[@]}" "${__hsp_namerefs[@]}"
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
#   - `HS_ERR_STATE_VAR_UNINITIALIZED` if `-S <statevar>` is missing.
#   - `HS_ERR_INVALID_VAR_NAME` if the state variable name or a requested
#     destroy variable name is not a valid Bash identifier.
#   - `HS_ERR_VAR_NAME_NOT_IN_STATE` if a requested destroy variable is not
#     present in the input state object.
#   - `HS_ERR_CORRUPT_STATE` if the input state object cannot be parsed or
#     rebuilt safely.
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

    # HS2 fast path: pure-Bash, no subprocess.
    if [[ "$__existing_state" == HS2:* ]]; then
        local -a __hsd2_recs=()
        _hs_hs2_parse hs_destroy_state "$__existing_state" __hsd2_recs || return $?
        local -A __hsd2_present=()
        local __hsd2_rec
        for __hsd2_rec in "${__hsd2_recs[@]}"; do
            __hsd2_present["$(_hs_hs2_record_name "$__hsd2_rec")"]=1
        done
        for __var_name in "${__destroy_var_args[@]}"; do
            if [[ -z "${__hsd2_present[$__var_name]-}" ]]; then
                echo "[ERROR] hs_destroy_state: variable '$__var_name' is not defined in the state." >&2
                return "$HS_ERR_VAR_NAME_NOT_IN_STATE"
            fi
        done
        local -A __hsd2_destroy_set=()
        for __var_name in "${__destroy_var_args[@]}"; do
            __hsd2_destroy_set["$__var_name"]=1
        done
        local -a __hsd2_survivors=()
        for __hsd2_rec in "${__hsd2_recs[@]}"; do
            local __hsd2_rname
            __hsd2_rname=$(_hs_hs2_record_name "$__hsd2_rec")
            [[ -z "${__hsd2_destroy_set[$__hsd2_rname]-}" ]] && __hsd2_survivors+=("$__hsd2_rec")
        done
        if (( ${#__hsd2_survivors[@]} > 0 )); then
            _hs_hs2_build "$__output_state_var" "" "${__hsd2_survivors[@]}"
        else
            printf -v "$__output_state_var" '%s' ""
        fi
        return 0
    fi

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
    #   1. inherits the minimal exported helpers and error-code constants
    #      required by _hs_resolve_state_inputs and hs_persist_state_as_code,
    #   2. declares every survivor variable local,
    #   3. evals the incoming state to restore those locals,
    #   4. calls the stdout form of hs_persist_state_as_code on the survivor list.
    #
    # Exporting the needed helpers avoids embedding their full function bodies
    # with declare -f while still keeping the subprocess independent from the
    # caller's test harness or shell startup files.
    local -a __keep_state_args=("${!__state_var_set[@]}")
    if (( ${#__keep_state_args[@]} > 0 )); then

        __output=$(
            (
                export HS_ERR_RESERVED_VAR_NAME HS_ERR_VAR_NAME_COLLISION \
                    HS_ERR_MULTIPLE_STATE_INPUTS HS_ERR_CORRUPT_STATE \
                    HS_ERR_INVALID_VAR_NAME HS_ERR_STATE_VAR_UNINITIALIZED \
                    HS_ERR_INVALID_ARGUMENT_TYPE HS_ERR_VAR_ALREADY_SET
                declare -fx _hs_is_array _hs_is_valid_variable_name \
                    _hs_resolve_state_inputs hs_persist_state_as_code

                # shellcheck disable=SC2016
                timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
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
                        printf "%s" "$__rebuilt_state"
                    }
                    _hs_destroy_state_rebuild "$@"
                ' bash "$__existing_state" "${__keep_state_args[@]}"
            )
        )
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
#   Restores the values of the specified local variables from the opaque state
#   object held in the variable named by -S.
#   Preferred (implicit) form — no -- and no variable names: emits a restore
#   snippet to stdout that the caller must eval; the snippet uses local -p in
#   the caller's scope so it can only target unset scalar locals of the
#   immediate caller, making it provably free of global scope pollution.
#   Explicit form — variable names supplied after --: restores each name by
#   traversing the full dynamic scope (caller chain and globals). Use when
#   targeting a variable in a higher-level caller or a declared global.
#   With -- and no variable names: returns 0 without restoring anything,
#   disabling the implicit-probe path.
# Options:
#   -q - suppresses the warning that is normally emitted when a requested
#        state variable is not present in the state object. Does not suppress
#        errors.
#   -S <state> - pass the state object by name, mandatory.
#   Other options are ignored up to the last --, so this function is usually able
#   to directly process its caller's argument list, future-proofing it against
#   new hs_read_persisted_state options.
#   -- - marks the end of options and the beginning of the list of variable names.
# Arguments:
#   $@ - names of variables to restore (explicit form). Without `--`, the
#        trailing arguments that are valid Bash identifiers are treated as the
#        variable list. Note that the value associated with the last given
#        option will be mistaken for a variable unless that option is known or
#        `--` is used.
# Errors:
#   - `HS_ERR_MISSING_ARGUMENT` if no state variable name is supplied at all.
#   - `HS_ERR_INVALID_VAR_NAME` if the state variable name or a requested
#     restore variable name is not a valid Bash identifier.
#   - `HS_ERR_STATE_VAR_UNINITIALIZED` if `-S <statevar>` is missing, or if
#     the named state variable is unset or empty.
#   - `HS_ERR_CORRUPT_STATE` if the state object cannot be evaluated safely
#     while restoring requested variables.
#   - `HS_ERR_UNKNOWN_VAR_NAME` if a requested variable name (explicit form)
#     is not declared anywhere in the dynamic scope.
#   - `HS_ERR_VAR_ALREADY_SET` if a requested variable name (explicit form)
#     is set (including empty string); unset it first if an overwrite is intended.
#   - Missing requested variables are warnings, one per variable, unless `-q`
#     is supplied.
# Usage examples:
#   # Preferred: implicit form, targets only the caller's own unset locals.
#   cleanup() {
#       local temp_file resource_id
#       eval "$(hs_read_persisted_state "$@")" || return $?
#       rm -f "$temp_file"
#       printf 'Cleaned up resource: %s\n' "$resource_id"
#   }
#   # Explicit form: use when targeting a specific subset or higher-scope vars.
#   cleanup() {
#       local temp_file resource_id
#       hs_read_persisted_state "$@" -- temp_file resource_id || return $?
#       rm -f "$temp_file"
#       printf 'Cleaned up resource: %s\n' "$resource_id"
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
        # HS2 fast path: pure-Bash, no subprocess.
        if [[ "$__existing_state" == HS2:* ]]; then
            local -a __hsrr_recs=()
            _hs_hs2_parse hs_read_persisted_state "$__existing_state" __hsrr_recs || return $?
            local -A __hsrr_map=()
            local __hsrr_r
            for __hsrr_r in "${__hsrr_recs[@]}"; do
                __hsrr_map["$(_hs_hs2_record_name "$__hsrr_r")"]="$__hsrr_r"
            done
            local __requested_var
            for __requested_var in "${__requested_var_args[@]}"; do
                if [[ -z "${__hsrr_map[$__requested_var]+x}" ]]; then
                    [[ "$__quiet" == "false" ]] && \
                        echo "[WARNING] hs_read_persisted_state: variable '$__requested_var' is not defined in the state." >&2
                    continue
                fi
                local __hsrr_rec="${__hsrr_map[$__requested_var]}"
                local __hsrr_flags="${__hsrr_rec#declare }"
                __hsrr_flags="${__hsrr_flags%% *}"
                if [[ "$__hsrr_flags" == *n* ]]; then
                    echo "[ERROR] hs_read_persisted_state: '$__requested_var' is a nameref; use the eval form to restore namerefs." >&2
                    return "$HS_ERR_CORRUPT_STATE"
                fi
                local __hsrr_caller_decl
                if ! __hsrr_caller_decl=$(declare -p "$__requested_var" 2>/dev/null); then
                    echo "[ERROR] hs_read_persisted_state: '$__requested_var' is not declared in scope." >&2
                    return "$HS_ERR_UNKNOWN_VAR_NAME"
                fi
                if [[ "$__hsrr_caller_decl" == *=* ]]; then
                    echo "[ERROR] hs_read_persisted_state: '$__requested_var' is already set; refusing to overwrite." >&2
                    return "$HS_ERR_VAR_ALREADY_SET"
                fi
                if [[ "$__hsrr_rec" == *=* ]]; then
                    local __hsrr_valpart="${__hsrr_rec#*=}"
                    local -n __hsrr_ref="$__requested_var"
                    eval "__hsrr_ref=${__hsrr_valpart}" || {
                        echo "[ERROR] hs_read_persisted_state: failed to restore '$__requested_var'." >&2
                        return "$HS_ERR_CORRUPT_STATE"
                    }
                    unset -n __hsrr_ref
                fi
            done
            return 0
        fi

        local __requested_var
        local __restored_payload=""
        local __restore_status=0
        # Evaluate the persisted state in a single short-lived Bash subprocess,
        # restore all requested variables there, and return one
        # associative-array initializer of restored string values. Missing
        # variables are reported directly on stderr from that subprocess.
        # shellcheck disable=SC2016
        __restored_payload=$(timeout --preserve-status -k 2 1 "${BASH:-bash}" --noprofile -lc '
            _hs_read_requested_state_vars() {
                local __state=$1
                local __quiet_mode=$2
                shift 2
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
            if ! declare -p "$__requested_var" >/dev/null 2>&1; then
                echo "[ERROR] hs_read_persisted_state: '$__requested_var' is not declared in scope." >&2
                return "$HS_ERR_UNKNOWN_VAR_NAME"
            fi
            if [[ "${!__requested_var+x}" ]]; then
                echo "[ERROR] hs_read_persisted_state: '$__requested_var' is already set; refusing to overwrite." >&2
                return "$HS_ERR_VAR_ALREADY_SET"
            fi
            local -n __requested_var_ref="$__requested_var"
            __requested_var_ref="${__restored_map[$__requested_var]}"
        done
        return 0
    fi

    # Step 4: if the caller used an explicit `--` but provided no variable
    # names after it, do not emit the implicit restore snippet. This lets
    # callers disable the stdout/eval path intentionally.
    if [[ -n "$__has_separator" ]]; then
        return 0
    fi

    # Step 5: otherwise, generate an implicit restore snippet. The snippet
    # inspects the current function's locals with `local -p`, selects unset
    # locals, and reenters hs_read_persisted_state with -q so unrelated
    # locals stay quiet. For HS2 state, namerefs are restored inline.
    local __probe_snippet=""
    local __hsi_sv
    __hsi_sv=$(printf '%q' "$__output_state_var")

    if [[ "$__existing_state" == HS2:* ]]; then
        # Parse state to discover nameref records for inline restoration.
        local -a __hsi_recs=()
        _hs_hs2_parse hs_read_persisted_state "$__existing_state" __hsi_recs || return $?
        local -A __hsi_nr_targets=()
        local __hsi_r
        for __hsi_r in "${__hsi_recs[@]}"; do
            local __hsi_rf="${__hsi_r#declare }"
            __hsi_rf="${__hsi_rf%% *}"
            if [[ "$__hsi_rf" == *n* && "$__hsi_r" == *=* ]]; then
                local __hsi_rn
                __hsi_rn=$(_hs_hs2_record_name "$__hsi_r")
                local __hsi_rt="${__hsi_r#*\"}"
                __hsi_rt="${__hsi_rt%\"}"
                __hsi_nr_targets["$__hsi_rn"]="$__hsi_rt"
            fi
        done

        # Part 1: explicit restore for non-nameref unset locals (scalars + arrays).
        IFS= read -r -d '' __probe_snippet <<EOF || true
hs_read_persisted_state -q -S ${__hsi_sv} -- \$(
  local -p | while IFS= read -r __hs_local_decl; do
    [[ "\$__hs_local_decl" == *=* ]] && continue
    [[ "\$__hs_local_decl" =~ ^declare\ -[^[:space:]]*n ]] && continue
    __hs_local_name=\${__hs_local_decl##* }
    [[ "\$__hs_local_name" == __hs_* ]] && continue
    printf '%s ' "\$__hs_local_name"
  done
) >/dev/null
EOF
        # Part 2: inline nameref restores guarded by caller's local -n declaration.
        local __hsi_nrn __hsi_nrt __hsi_qn __hsi_qt
        for __hsi_nrn in "${!__hsi_nr_targets[@]}"; do
            __hsi_nrt="${__hsi_nr_targets[$__hsi_nrn]}"
            __hsi_qn=$(printf '%q' "$__hsi_nrn")
            __hsi_qt=$(printf '%q' "$__hsi_nrt")
            __probe_snippet+="[[ \"\$(declare -p ${__hsi_qn} 2>/dev/null)\" == 'declare -'*n*' ${__hsi_qn}' ]] && declare -n ${__hsi_qn}=${__hsi_qt}"$'\n'
        done
    else
        IFS= read -r -d '' __probe_snippet <<EOF || true
hs_read_persisted_state -q -S ${__hsi_sv} -- \$(
  local -p | while IFS= read -r __hs_local_decl; do
    [[ "\$__hs_local_decl" == *=* ]] && continue
    [[ "\$__hs_local_decl" =~ ^declare\ -[^[:space:]]*[aA] ]] && continue
    __hs_local_name=\${__hs_local_decl##* }
    [[ "\$__hs_local_name" == __hs_* ]] && continue
    printf '%s ' "\$__hs_local_name"
  done
) >/dev/null
EOF
    fi
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
#   Parses helper options for state-oriented functions. Parsed results are
#   returned to the caller through the array variables named in `$2` and `$4`.
#   The helper recognizes `-S <statevar>` when requested by `$3`, optional
#   helper flags such as `-q`, unknown forwarded options, and an optional
#   final `--` separator before an explicit variable-name list.
# Arguments:
#   $1 - caller function name, used in error messages; must be a valid Bash name
#   $2 - name of the indexed array variable that will receive forwarded,
#        unprocessed arguments; must be a valid Bash name
#   $3 - `getopts` format string of accepted helper options; e.g. `qS:`
#   $4 - name of the associative array variable that will receive processed
#        arguments; must be a valid Bash name
#   $5... - forwarded arguments from the public helper caller; if `--` is
#           present, its last occurrence marks the start of the explicit
#           variable-name list
# Returns:
#   0 on success.
#   On success, `$4` may contain:
#     - `state`: the validated state variable name from `-S`
#     - `quiet`: `true` or `false`
#     - `vars`: the validated explicit variable-name list as a space-separated string
#     - `separator`: set when an explicit `--` was seen
#   `HS_ERR_MISSING_ARGUMENT` if a required option parameter such as the value
#   for `-S` is missing.
#   `HS_ERR_INVALID_VAR_NAME` if `$2` or `$4` collides with a local variable
#   name in this helper.
#   `HS_ERR_INVALID_ARGUMENT_TYPE` if `$2` is not an indexed array variable or
#   if `$4` is not an associative array variable.
#   `HS_ERR_INVALID_VAR_NAME` if the state variable name or an explicit
#   variable-name token is not a valid Bash identifier.
#   `HS_ERR_STATE_VAR_UNINITIALIZED` if no `-S <statevar>` option is provided.
# Usage:
#   local -a remaining_args=()
#   local -A processed_args=()
#   _hs_resolve_state_inputs my_helper remaining_args qS: processed_args "$@" || return $?
_hs_resolve_state_inputs() {
    if [ $# -lt 4 ]; then
        echo "[ERROR] $1: missing required arguments; expected at least 4 parameters." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi
    local __arg
    local __caller_name=$1
    local __options=$3
    local __current_option
    local -i OPTIND=1
    local -i __last_separator_index
    local -i __scan_index
    local -a __trailing_vars=()
    local -n __remaining_args_ref
    local -n __processed_args_ref
    for __arg in "$1" "$2" "$4"; do
        if ! _hs_is_valid_variable_name "$__arg"; then
            echo "[ERROR] $1: invalid variable name '$__arg'." >&2
            return "$HS_ERR_INVALID_VAR_NAME"
        fi
    done
    if local -p "$2" >/dev/null 2>&1; then
        echo "[ERROR] ${__caller_name}: '$2' conflicts with a local variable name and cannot be used here." >&2
        return "$HS_ERR_INVALID_VAR_NAME"
    fi
    if local -p "$4" >/dev/null 2>&1; then
        echo "[ERROR] ${__caller_name}: '$4' conflicts with a local variable name and cannot be used here." >&2
        return "$HS_ERR_INVALID_VAR_NAME"
    fi

    __remaining_args_ref=$2
    __processed_args_ref=$4
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
    
    # Force a colon in front of $__options to record unknown options in $OPTARG
    while (( "$#" >= "$OPTIND" )); do
        __scan_index=${OPTIND}
        if getopts ":$__options" __current_option; then
            # Returns OK if known or unknown option -X [val]
            # value is assigned to $OPTARG for known options
            # value can be attached -Svarname or detached -S varname
            case "$__current_option" in
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
        elif (( "$__scan_index" == "$OPTIND" )); then
            # It was a word (parameter to some unknown option)
            __remaining_args_ref+=("${!OPTIND}")
            OPTIND=$(( OPTIND + 1 ))
        else
            # Hit --. Only the last separator counts. Preserve any earlier
            # separator and the tokens up to the final separator as forwarded
            # caller arguments, then treat only the suffix after the final
            # separator as the explicit variable list.
            __processed_args_ref["separator"]=true
            __last_separator_index=$((OPTIND - 1))
            for ((__scan_index = OPTIND; __scan_index <= $#; __scan_index++)); do
                if [[ "${!__scan_index}" == "--" ]]; then
                    __last_separator_index=$__scan_index
                fi
            done
            if (( __last_separator_index > OPTIND - 1 )); then
                __remaining_args_ref+=("--")
            fi
            while (( OPTIND < __last_separator_index )); do
                __remaining_args_ref+=("${!OPTIND}")
                OPTIND=$(( OPTIND + 1 ))
            done
            OPTIND=$(( __last_separator_index + 1 ))
            break
        fi
    done

    # Pull variable names from the end
    : "${__processed_args_ref["vars"]:=}"
    if [[ -n "${__processed_args_ref[separator]-}" ]]; then
        while (( "$#" >= "$OPTIND" )); do
            if ! _hs_is_valid_variable_name "${!OPTIND}"; then
                echo "[ERROR] ${__caller_name}: invalid variable name '${!OPTIND}'." >&2
                return "$HS_ERR_INVALID_VAR_NAME"
            fi
            printf -v __processed_args_ref["vars"] "%s%s " "${__processed_args_ref['vars']}" "${!OPTIND}"
            OPTIND=$(( OPTIND + 1 ))
        done
    else
        # Without an explicit separator, treat the maximal suffix of valid
        # variable names as the library-owned var list. We peel that suffix
        # from the end, then rebuild it in original argument order.
        while (( ${#__remaining_args_ref[@]} > 0 )) && _hs_is_valid_variable_name "${__remaining_args_ref[-1]}"; do
            __trailing_vars=("${__remaining_args_ref[-1]}" "${__trailing_vars[@]}")
            unset "__remaining_args_ref[-1]"
        done
        local IFS=' '
        __processed_args_ref["vars"]="${__trailing_vars[*]}"
        if [[ "${__processed_args_ref[quiet]}" == false ]] && ((${#__remaining_args_ref[@]} > 0)); then
            echo "[WARNING] ${__caller_name}: forwarded arguments remain after implicit variable-list parsing; use -- before the variable names." >&2
        fi
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

# --- HS2 helper functions -------------------------------------------------------

# _hs_strip_export <decl>
# Prints a declare -p record with the export flag (-x) removed.
_hs_strip_export() {
    local __decl="$1"
    if [[ "$__decl" != "declare -"*x* ]]; then
        printf '%s' "$__decl"
        return 0
    fi
    local __rest="${__decl#declare }"
    local __attrs="${__rest%% *}"
    local __nameandval="${__rest#* }"
    __attrs="${__attrs//x/}"
    [[ "$__attrs" == "-" ]] && __attrs="--"
    printf 'declare %s %s' "$__attrs" "$__nameandval"
}

# _hs_hs2_record_name <record>
# Prints the variable name from a declare -p record.
_hs_hs2_record_name() {
    local __rest="${1#declare }"
    __rest="${__rest#* }"
    printf '%s' "${__rest%%=*}"
}

# _hs_hs2_build <out_var> <existing_payload> [record ...]
# Builds an HS2 state string from existing payload and new records and writes
# it to the variable named by <out_var>.
_hs_hs2_build() {
    local __hs2b_out="$1"
    local __hs2b_payload="$2"
    shift 2
    local __hs2b_rec
    for __hs2b_rec in "$@"; do
        if [[ -n "$__hs2b_payload" ]]; then
            __hs2b_payload+=$'\001'
        fi
        __hs2b_payload+="$__hs2b_rec"
    done
    local __hs2b_cksum
    __hs2b_cksum=$(printf '%s' "$__hs2b_payload" | cksum)
    __hs2b_cksum="${__hs2b_cksum%% *}"
    printf -v "$__hs2b_out" 'HS2:%s:%s' "$__hs2b_cksum" "$__hs2b_payload"
}

# _hs_hs2_parse <caller> <state> <out_array>
# Verifies an HS2 state string and splits its records (SOH-delimited) into the
# indexed array named by <out_array>.
_hs_hs2_parse() {
    local __hs2p_caller="$1"
    local __hs2p_state="$2"
    local -n __hs2p_out="$3"

    if [[ "$__hs2p_state" != HS2:* ]]; then
        echo "[ERROR] ${__hs2p_caller}: state is not in HS2 format." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi
    local __hs2p_rest="${__hs2p_state#HS2:}"
    local __hs2p_stored="${__hs2p_rest%%:*}"
    local __hs2p_payload="${__hs2p_rest#*:}"

    local __hs2p_computed
    __hs2p_computed=$(printf '%s' "$__hs2p_payload" | cksum)
    __hs2p_computed="${__hs2p_computed%% *}"
    if [[ "$__hs2p_stored" != "$__hs2p_computed" ]]; then
        echo "[ERROR] ${__hs2p_caller}: HS2 state checksum mismatch." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi

    __hs2p_out=()
    [[ -z "$__hs2p_payload" ]] && return 0
    local __hs2p_old_ifs="$IFS"
    IFS=$'\001' read -ra __hs2p_out <<< "$__hs2p_payload"
    IFS="$__hs2p_old_ifs"
}
