#!/bin/bash
# File: config/handle_state.sh
# Description: Helper functions to carry state information between initialization and cleanup functions.
# Author: Jean-Marc Le Peuvédic (https://calcool.ai)

# Sentinel
[[ -z ${__HANDLE_STATE_SH_INCLUDED:-} ]] && __HANDLE_STATE_SH_INCLUDED=1 || return 0

# Source command guard for secure external command usage
# shellcheck source=command_guard.sh
source "${BASH_SOURCE%/*}/command_guard.sh"

# Library usage — see docs/libraries/handle_state.rst for the full API.

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


# --- hs_persist_state ----------------------------------------------------------
# Function:
#   hs_persist_state [options] [--] [state_variable ...]
# Description:
#   Appends the current values of the specified local variables to an HS2-format
#   opaque state object held in the variable named by -S. Supports scalars,
#   indexed arrays, associative arrays, and namerefs (nameref target must also
#   be persisted in the same call or already present in the prior state).
# Options:
#   -S <state> - pass the state object by name, mandatory.
#   Other options are ignored up to the last --, so this function is usually able
#   to directly process its caller's argument list, future-proofing it against
#   new hs_persist_state options.
#   -- - marks the end of options and the beginning of the list of variable names.
#   --list-reserved - prints the reserved internal variable names to stdout, one
#     per line, and returns 0. Incompatible with all other options. Intended for
#     testing only. The reported names are also reported by hs_read_persisted_state
#     and hs_destroy_state --list-reserved (identical output across all three).
# Arguments:
#   $@ - names of local variables to persist. Without `--`, the trailing
#        arguments that are valid Bash identifiers are treated as the variable
#        list. Note that the value associated with the last given option will be
#        mistaken for a variable unless `--` is used.
# Errors:
#   - `HS_ERR_MISSING_ARGUMENT` if no state variable name is supplied at all.
#   - `HS_ERR_INVALID_VAR_NAME` if the state variable name or a requested
#     persist variable name is not a valid Bash identifier.
#   - `HS_ERR_STATE_VAR_UNINITIALIZED` if `-S <statevar>` is missing.
#   - `HS_ERR_CORRUPT_STATE` if the existing state is not in HS2 format or
#     the rebuilt state cannot be verified.
#   - `HS_ERR_RESERVED_VAR_NAME` if a requested name starts with `__hs_`,
#     which is the reserved internal name prefix used by this library.
#   - `HS_ERR_VAR_NAME_COLLISION` if a requested name is already present in
#     the existing state object.
#   - `HS_ERR_UNKNOWN_VAR_NAME` if a requested name is not declared in scope,
#     or is a function name rather than a variable.
#   - `HS_ERR_NAMEREF_TARGET_NOT_PERSISTED` if a nameref's target is not being
#     persisted in the same call and is not already present in the prior state.
# Usage examples:
#   init_function() {
#       local token="abc" count=3
#       hs_persist_state "$@" -- token count || return $?
#   }
#   init_with_array() {
#       local -a items=(one two three)
#       hs_persist_state -S "$1" -- items || return $?
#   }
hs_persist_state() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    if [[ "${1-}" == "--list-reserved" ]]; then
        local list_reserved=1
        shift
        if [ $# -gt 0 ]; then
            echo "[ERROR] hs_persist_state: --list-reserved takes no other arguments." >&2
            return "$HS_ERR_INVALID_ARGUMENT_TYPE"
        fi
    else
        _hs_resolve_state_inputs hs_persist_state S: "$@" || return $?
        # $() absorbs the helper's exit status; embedding "return N" in the output
        # lets the surrounding eval propagate the failure to the caller.
        eval "$(_hs_ps_body "${__hs_processed[state]}" "${__hs_processed[vars]-}" \
            || printf 'return %d' "$?")" || return $?
    fi
    # List reserved
    if _hs_local_exists "$(local -p)" list_reserved; then
        # Snapshot taken after all processing locals are declared. local -p runs
        # in a subshell before the assignment completes, so lp_snapshot itself
        # is absent from the output. Splitting declare+assign would cause
        # lp_snapshot to appear in its own snapshot; the combined form is
        # intentional here.
        # shellcheck disable=SC2155
        local lp_snapshot="$(local -p)"
        _hs_print_reserved_names "$lp_snapshot" list_reserved
    fi
}

# _hs_ps_body <out_var> <vars_str>
# Contains the validation and build logic for hs_persist_state. Runs in its
# own frame so its locals do not appear in the entry point's collision section.
_hs_ps_body() {
    local existing="${!1-}"
    local out_var="$1"
    local -a vars=()
    read -r -a vars <<< "${2-}"

    # Parse existing state (must be empty or HS2).
    local existing_payload=""
    local -a existing_recs=()
    local -A existing_names=()
    if [[ -n "$existing" ]]; then
        if [[ "$existing" != HS2:* ]]; then
            echo "[ERROR] hs_persist_state: existing state is not in HS2 format." >&2
            return "$HS_ERR_CORRUPT_STATE"
        fi
        _hs_hs2_parse hs_persist_state "$existing" existing_recs || return $?
        existing_payload="${existing#HS2:}"
        existing_payload="${existing_payload#*:}"
        local existing_rec
        for existing_rec in "${existing_recs[@]}"; do
            existing_names["$(_hs_hs2_record_name "$existing_rec")"]=1
        done
    fi

    # Phase 1: validate all names; separate non-namerefs from namerefs.
    local -a non_namerefs=()
    local -a namerefs=()
    local -A this_call=()
    local var decl flags
    for var in "${vars[@]}"; do
        if [[ -n "${existing_names[$var]-}" ]]; then
            echo "[ERROR] hs_persist_state: variable '$var' already exists in the state." >&2
            return "$HS_ERR_VAR_NAME_COLLISION"
        fi
        if ! decl=$(declare -p "$var" 2>/dev/null); then
            if declare -f "$var" >/dev/null 2>&1; then
                echo "[ERROR] hs_persist_state: '$var' is a function, not a variable." >&2
            else
                echo "[ERROR] hs_persist_state: '$var' is not declared in scope." >&2
            fi
            return "$HS_ERR_UNKNOWN_VAR_NAME"
        fi
        flags="${decl#declare }"
        flags="${flags%% *}"
        if [[ "$flags" == *n* ]]; then
            this_call["$var"]=nameref
        else
            non_namerefs+=("$(_hs_strip_export "$decl")")
            this_call["$var"]=1
        fi
    done

    # Phase 2: validate nameref targets and build nameref records (after targets).
    local target
    for var in "${vars[@]}"; do
        [[ "${this_call[$var]-}" == nameref ]] || continue
        decl=$(declare -p "$var" 2>/dev/null)
        target="${decl#*\"}"
        target="${target%\"}"
        if [[ -z "${existing_names[$target]-}" && \
              -z "${this_call[$target]-}" ]]; then
            echo "[ERROR] hs_persist_state: nameref '$var' target '$target' is not being persisted." >&2
            return "$HS_ERR_NAMEREF_TARGET_NOT_PERSISTED"
        fi
        namerefs+=("$(_hs_strip_export "$decl")")
    done

    # Build HS2 state: existing payload + non-nameref records + nameref records.
    # Print the assignment statement; the entry point evals it so no helper
    # ever writes directly into a caller's variable.
    local new_state
    new_state=$(_hs_hs2_build "$existing_payload" \
        "${non_namerefs[@]}" "${namerefs[@]}") || return $?
    printf '%s=%s\n' "$out_var" "$(printf '%q' "$new_state")"
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
#   --list-reserved - prints the reserved internal variable names to stdout, one
#     per line, and returns 0. Incompatible with all other options. Intended for
#     testing only. See hs_persist_state --list-reserved for the authoritative list.
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
    local -a __hs_remaining=()
    local -A __hs_processed=()
    if [[ "${1-}" == "--list-reserved" ]]; then
        local list_reserved=1
        shift
        if [ $# -gt 0 ]; then
            echo "[ERROR] hs_destroy_state: --list-reserved takes no other arguments." >&2
            return "$HS_ERR_INVALID_ARGUMENT_TYPE"
        fi
    else
        _hs_resolve_state_inputs hs_destroy_state S: "$@" || return $?
        # $() absorbs the helper's exit status; embedding "return N" in the output
        # lets the surrounding eval propagate the failure to the caller.
        eval "$(_hs_ds_body "${__hs_processed[state]}" "${__hs_processed[vars]-}" \
            || printf 'return %d' "$?")" || return $?
    fi
    if _hs_local_exists "$(local -p)" list_reserved; then
        # Snapshot taken after all processing locals are declared. local -p runs
        # in a subshell before the assignment completes, so lp_snapshot itself
        # is absent from the output. Splitting declare+assign would cause
        # lp_snapshot to appear in its own snapshot; the combined form is
        # intentional here.
        # shellcheck disable=SC2155
        local lp_snapshot="$(local -p)"
        _hs_print_reserved_names "$lp_snapshot" list_reserved
    fi
}

# _hs_ds_body <out_var> <vars_str>
# Contains the validation and rebuild logic for hs_destroy_state. Runs in its
# own frame so its locals do not appear in the entry point's collision section.
_hs_ds_body() {
    local out_var="$1"
    local -a vars=()
    read -r -a vars <<< "${2-}"
    local existing="${!out_var-}"

    if [[ "$existing" != HS2:* ]]; then
        echo "[ERROR] hs_destroy_state: state is not in HS2 format." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi

    local -a recs=()
    _hs_hs2_parse hs_destroy_state "$existing" recs || return $?
    local -A present=()
    local rec
    for rec in "${recs[@]}"; do
        present["$(_hs_hs2_record_name "$rec")"]=1
    done

    local var
    for var in "${vars[@]}"; do
        if [[ -z "${present[$var]-}" ]]; then
            echo "[ERROR] hs_destroy_state: variable '$var' is not defined in the state." >&2
            return "$HS_ERR_VAR_NAME_NOT_IN_STATE"
        fi
    done

    local -A destroy_set=()
    for var in "${vars[@]}"; do
        destroy_set["$var"]=1
    done
    local -a survivors=()
    local record_name
    for rec in "${recs[@]}"; do
        record_name=$(_hs_hs2_record_name "$rec")
        [[ -z "${destroy_set[$record_name]-}" ]] && survivors+=("$rec")
    done

    # Print the assignment statement; the entry point evals it so no helper
    # ever writes directly into a caller's variable.
    local new_state
    if (( ${#survivors[@]} > 0 )); then
        new_state=$(_hs_hs2_build "" "${survivors[@]}") || return $?
        printf '%s=%s\n' "$out_var" "$(printf '%q' "$new_state")"
    else
        printf '%s=\n' "$out_var"
    fi
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
#   --list-reserved - prints the reserved internal variable names to stdout, one
#     per line, and returns 0. Incompatible with all other options. Intended for
#     testing only. See hs_persist_state --list-reserved for the authoritative list.
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
    local -a __hs_remaining=()
    local -A __hs_processed=()
    if [[ "${1-}" == "--list-reserved" ]]; then
        local list_reserved=1
        shift
        if [ $# -gt 0 ]; then
            echo "[ERROR] hs_read_persisted_state: --list-reserved takes no other arguments." >&2
            return "$HS_ERR_INVALID_ARGUMENT_TYPE"
        fi
    else
        if [[ "${1-}" != -* ]]; then
            set -- -S "$@"
        fi
        _hs_resolve_state_inputs hs_read_persisted_state qS: "$@" || return $?
        if [[ -n "${__hs_processed[vars]-}" ]]; then
            # $() absorbs the helper's exit status; embedding "return N" in the
            # output lets the surrounding eval propagate the failure to the caller.
            eval "$(_hs_rr_explicit_stmts "${__hs_processed[state]}" \
                "${__hs_processed[quiet]}" "${__hs_processed[vars]}" \
                || printf 'return %d' "$?")" || return $?
            return 0
        fi
        [[ -n "${__hs_processed[separator]-}" ]] && return 0
        _hs_rr_implicit_snippet "${__hs_processed[state]}" || return $?
    fi
    if _hs_local_exists "$(local -p)" list_reserved; then
        # Snapshot taken after all processing locals are declared. local -p runs
        # in a subshell before the assignment completes, so lp_snapshot itself
        # is absent from the output. Splitting declare+assign would cause
        # lp_snapshot to appear in its own snapshot; the combined form is
        # intentional here.
        # shellcheck disable=SC2155
        local lp_snapshot="$(local -p)"
        _hs_print_reserved_names "$lp_snapshot" list_reserved
    fi
}

# _hs_rr_explicit_stmts <state_var> <quiet> <vars_str>
# Validates all requested variables (declared and unset in dynamic scope), then
# prints one assignment statement per variable to stdout. The caller evals the
# output in the entry point's frame so assignments traverse dynamic scope and
# none of this helper's locals are in the collision section.
_hs_rr_explicit_stmts() {
    local existing="${!1-}"
    local state_var="$1"
    local quiet="$2"
    local -a requested=()
    read -r -a requested <<< "${3-}"
 
    if [ -z "$existing" ]; then
        echo "[ERROR] hs_read_persisted_state: state variable '$state_var' is not set or is empty." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi
    if [[ "$existing" != HS2:* ]]; then
        echo "[ERROR] hs_read_persisted_state: state is not in HS2 format." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi

    local -a recs=()
    _hs_hs2_parse hs_read_persisted_state "$existing" recs || return $?
    local -A record_map=()
    local rec
    for rec in "${recs[@]}"; do
        record_map["$(_hs_hs2_record_name "$rec")"]="$rec"
    done

    # Phase 1: all-or-nothing guard check.
    local var caller_decl
    for var in "${requested[@]}"; do
        [[ -z "${record_map[$var]+x}" ]] && continue
        if ! caller_decl=$(declare -p "$var" 2>/dev/null); then
            echo "[ERROR] hs_read_persisted_state: '$var' is not declared in scope." >&2
            return "$HS_ERR_UNKNOWN_VAR_NAME"
        fi
        if [[ "$caller_decl" == *=* ]]; then
            echo "[ERROR] hs_read_persisted_state: '$var' is already set; refusing to overwrite." >&2
            return "$HS_ERR_VAR_ALREADY_SET"
        fi
    done

    # Phase 2: generate assignment statements (eval'd by the entry point).
    local record value_part
    for var in "${requested[@]}"; do
        if [[ -z "${record_map[$var]+x}" ]]; then
            [[ "$quiet" == "false" ]] && \
                echo "[WARNING] hs_read_persisted_state: variable '$var' is not defined in the state." >&2
            continue
        fi
        record="${record_map[$var]}"
        if [[ "$record" == *=* ]]; then
            value_part="${record#*=}"
            printf '%s=%s\n' "$var" "$value_part"
        fi
    done
}

# _hs_rr_implicit_snippet <state_var>
# Emits the eval-able restore snippet for the implicit (no-variable-names) form
# of hs_read_persisted_state. Runs in its own frame; the snippet is eval'd by
# the caller of hs_read_persisted_state, not by the entry point.
_hs_rr_implicit_snippet() {
    local existing="${!1-}"
    local state_var="$1"

    if [ -z "$existing" ]; then
        echo "[ERROR] hs_read_persisted_state: state variable '$state_var' is not set or is empty." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi
    if [[ "$existing" != HS2:* ]]; then
        echo "[ERROR] hs_read_persisted_state: state is not in HS2 format." >&2
        return "$HS_ERR_CORRUPT_STATE"
    fi

    local -a recs=()
    _hs_hs2_parse hs_read_persisted_state "$existing" recs || return $?
    local -A nameref_targets=()
    local rec rec_flags rec_name rec_target
    for rec in "${recs[@]}"; do
        rec_flags="${rec#declare }"
        rec_flags="${rec_flags%% *}"
        if [[ "$rec_flags" == *n* && "$rec" == *=* ]]; then
            rec_name=$(_hs_hs2_record_name "$rec")
            rec_target="${rec#*\"}"
            rec_target="${rec_target%\"}"
            nameref_targets["$rec_name"]="$rec_target"
        fi
    done

    local escaped_state_var
    escaped_state_var=$(printf '%q' "$state_var")
    local snippet=""
    IFS= read -r -d '' snippet <<EOF || true
hs_read_persisted_state -q -S ${escaped_state_var} -- \$(
  local -p | while IFS= read -r __hs_local_decl; do
    [[ "\$__hs_local_decl" == *=* ]] && continue
    [[ "\$__hs_local_decl" =~ ^declare\ -[^[:space:]]*n ]] && continue
    __hs_local_name=\${__hs_local_decl##* }
    printf '%s ' "\$__hs_local_name"
  done
) >/dev/null
EOF

    local nameref_name nameref_target quoted_name quoted_target
    for nameref_name in "${!nameref_targets[@]}"; do
        nameref_target="${nameref_targets[$nameref_name]}"
        quoted_name=$(printf '%q' "$nameref_name")
        quoted_target=$(printf '%q' "$nameref_target")
        snippet+="[[ \"\$(declare -p ${quoted_name} 2>/dev/null)\" == 'declare -'*n*' ${quoted_name}' ]] && declare -n ${quoted_name}=${quoted_target}"$'\n'
    done
    printf '%s' "$snippet"
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
# _hs_local_exists <lp_snapshot> <name>
# Returns 0 if <name> appears as a declared local in the local -p snapshot,
# 1 otherwise. The snapshot must be captured with local -p in the caller's
# own frame so that only that frame's locals are visible — not ancestor frames.
# This avoids the dynamic-scope false-positive that [[ -v name ]] produces when
# an ancestor frame happens to declare a local with the same name.
_hs_local_exists() {
    local __hs_le_name="$2"
    local __hs_le_line __hs_le_n
    while IFS= read -r __hs_le_line; do
        [[ "$__hs_le_line" != declare\ * ]] && continue
        __hs_le_n="${__hs_le_line#* }"; __hs_le_n="${__hs_le_n#* }"; __hs_le_n="${__hs_le_n%%=*}"
        [[ "$__hs_le_n" == "$__hs_le_name" ]] && return 0
    done <<< "$1"
    return 1
}

_hs_is_valid_variable_name() {
    [[ "${1-}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# _hs_print_reserved_names <lp_snapshot> [exclude]
# Prints every variable name found in the local -p snapshot, one per line,
# skipping the single name given by the optional <exclude> argument. Called by
# the --list-reserved end block of each entry point; <exclude> is the mode-flag
# local (e.g. list_reserved) that is present only in --list-reserved mode and
# must not be reported as part of the collision section.
_hs_print_reserved_names() {
    local __hs_prn_snapshot="$1"
    local __hs_prn_exclude="${2-}"
    local declaration name
    while IFS= read -r declaration; do
        [[ "$declaration" != declare\ * ]] && continue
        name="${declaration#* }"; name="${name#* }"; name="${name%%=*}"
        [[ -n "$__hs_prn_exclude" && "$name" == "$__hs_prn_exclude" ]] && continue
        printf '%s\n' "$name"
    done <<< "$__hs_prn_snapshot"
}

# Function:
#   _hs_resolve_state_inputs
# Description:
#   Parses helper options for state-oriented functions. Parsed results are
#   written directly into the caller's `__hs_remaining` (indexed array) and
#   `__hs_processed` (associative array) variables via Bash dynamic scoping.
#   The helper recognizes `-S <statevar>` when requested by `$2`, optional
#   helper flags such as `-q`, unknown forwarded options, and an optional
#   final `--` separator before an explicit variable-name list.
# Caller contract:
#   The caller MUST declare the following variables before calling this helper:
#     local -a __hs_remaining=()
#     local -A __hs_processed=()
#   The helper writes its output into those exact names through dynamic scoping.
#   Passing any other names is a programming error.
# Arguments:
#   $1 - caller function name, used in error messages; must be a valid Bash name
#   $2 - `getopts` format string of accepted helper options; e.g. `qS:`
#   $3... - forwarded arguments from the public helper caller; if `--` is
#           present, its last occurrence marks the start of the explicit
#           variable-name list
# Returns:
#   0 on success.
#   On success, `__hs_processed` may contain:
#     - `state`: the validated state variable name from `-S`
#     - `quiet`: `true` or `false`
#     - `vars`: the validated explicit variable-name list as a space-separated string
#     - `separator`: set when an explicit `--` was seen
#   `HS_ERR_MISSING_ARGUMENT` if a required option parameter such as the value
#   for `-S` is missing.
#   `HS_ERR_INVALID_VAR_NAME` if the state variable name or an explicit
#   variable-name token is not a valid Bash identifier.
#   `HS_ERR_RESERVED_VAR_NAME` if the state variable name or a variable-name
#   token matches a name in the caller's --list-reserved output.
#   `HS_ERR_STATE_VAR_UNINITIALIZED` if no `-S <statevar>` option is provided.
# Usage:
#   local -a __hs_remaining=()
#   local -A __hs_processed=()
#   _hs_resolve_state_inputs my_helper qS: "$@" || return $?
_hs_resolve_state_inputs() {
    if [ $# -lt 2 ]; then
        echo "[ERROR] ${1-_hs_resolve_state_inputs}: missing required arguments." >&2
        return "$HS_ERR_MISSING_ARGUMENT"
    fi
    local __hs_ri_caller="$1"
    local __hs_ri_opts="$2"
    local __hs_ri_opt
    local OPTARG
    local -i OPTIND=1
    local -i __hs_ri_sep_idx=0
    local -i __hs_ri_scan=0
    local -i __hs_ri_last_opt_sz=0
    local -a __hs_ri_trailing=()
    shift 2

    # Verify caller declared the required output variables with correct types.
    if [[ "${__hs_remaining@a}" != *a* ]]; then
        echo "[ERROR] ${__hs_ri_caller}: caller must declare 'local -a __hs_remaining=()' before calling _hs_resolve_state_inputs." >&2
        return "$HS_ERR_INVALID_ARGUMENT_TYPE"
    fi
    if [[ "${__hs_processed@a}" != *A* ]]; then
        echo "[ERROR] ${__hs_ri_caller}: caller must declare 'local -A __hs_processed=()' before calling _hs_resolve_state_inputs." >&2
        return "$HS_ERR_INVALID_ARGUMENT_TYPE"
    fi

    __hs_processed=(["quiet"]=false)
    __hs_remaining=()

    local __hs_ri_reserved_list
    __hs_ri_reserved_list=$("$__hs_ri_caller" --list-reserved 2>/dev/null) || true

    while (( "$#" >= "$OPTIND" )); do
        __hs_ri_scan=${OPTIND}
        if getopts ":$__hs_ri_opts" __hs_ri_opt; then
            case "$__hs_ri_opt" in
                \?)
                    __hs_remaining+=("-$OPTARG")
                    ;;
                S)
                    if ! _hs_is_valid_variable_name "$OPTARG"; then
                        echo "[ERROR] ${__hs_ri_caller}: invalid variable name '${OPTARG}'." >&2
                        return "$HS_ERR_INVALID_VAR_NAME"
                    fi
                    if [[ -n "$__hs_ri_reserved_list" && \
                          $'\n'"$__hs_ri_reserved_list"$'\n' == *$'\n'"$OPTARG"$'\n'* ]]; then
                        echo "[ERROR] ${__hs_ri_caller}: state variable name '$OPTARG' is reserved; choose a different variable name." >&2
                        return "$HS_ERR_RESERVED_VAR_NAME"
                    fi
                    __hs_processed["state"]="$OPTARG"
                    __hs_ri_last_opt_sz=${#__hs_remaining[@]}
                    ;;
                q)
                    __hs_processed["quiet"]=true
                    __hs_ri_last_opt_sz=${#__hs_remaining[@]}
                    ;;
                :)
                    echo "[ERROR] ${__hs_ri_caller}: missing required parameter to option -${OPTARG}." >&2
                    return "$HS_ERR_MISSING_ARGUMENT"
                    ;;
            esac
        elif (( __hs_ri_scan == OPTIND )); then
            __hs_remaining+=("${!OPTIND}")
            OPTIND=$(( OPTIND + 1 ))
        else
            # Hit --. Find the last occurrence to handle multiple separators.
            __hs_processed["separator"]=true
            __hs_ri_sep_idx=$(( OPTIND - 1 ))
            for (( __hs_ri_scan = OPTIND; __hs_ri_scan <= $#; __hs_ri_scan++ )); do
                [[ "${!__hs_ri_scan}" == "--" ]] && __hs_ri_sep_idx=$__hs_ri_scan
            done
            if (( __hs_ri_sep_idx > OPTIND - 1 )); then
                __hs_remaining+=("--")
            fi
            while (( OPTIND < __hs_ri_sep_idx )); do
                __hs_remaining+=("${!OPTIND}")
                OPTIND=$(( OPTIND + 1 ))
            done
            OPTIND=$(( __hs_ri_sep_idx + 1 ))
            break
        fi
    done

    : "${__hs_processed["vars"]:=}"
    if [[ -n "${__hs_processed[separator]-}" ]]; then
        while (( "$#" >= "$OPTIND" )); do
            if ! _hs_is_valid_variable_name "${!OPTIND}"; then
                echo "[ERROR] ${__hs_ri_caller}: invalid variable name '${!OPTIND}'." >&2
                return "$HS_ERR_INVALID_VAR_NAME"
            fi
            if [[ -n "$__hs_ri_reserved_list" && \
                  $'\n'"$__hs_ri_reserved_list"$'\n' == *$'\n'"${!OPTIND}"$'\n'* ]]; then
                echo "[ERROR] ${__hs_ri_caller}: variable name '${!OPTIND}' is reserved." >&2
                return "$HS_ERR_RESERVED_VAR_NAME"
            fi
            printf -v '__hs_processed[vars]' "%s%s " "${__hs_processed[vars]}" "${!OPTIND}"
            OPTIND=$(( OPTIND + 1 ))
        done
    else
        while (( ${#__hs_remaining[@]} > __hs_ri_last_opt_sz )) && \
              _hs_is_valid_variable_name "${__hs_remaining[-1]}"; do
            if [[ -n "$__hs_ri_reserved_list" && \
                  $'\n'"$__hs_ri_reserved_list"$'\n' == *$'\n'"${__hs_remaining[-1]}"$'\n'* ]]; then
                echo "[ERROR] ${__hs_ri_caller}: variable name '${__hs_remaining[-1]}' is reserved." >&2
                return "$HS_ERR_RESERVED_VAR_NAME"
            fi
            __hs_ri_trailing=("${__hs_remaining[-1]}" "${__hs_ri_trailing[@]}")
            unset '__hs_remaining[-1]'
        done
        local IFS=' '
        __hs_processed["vars"]="${__hs_ri_trailing[*]}"
        if [[ "${__hs_processed[quiet]}" == false ]] && \
           (( ${#__hs_remaining[@]} > 0 )); then
            echo "[WARNING] ${__hs_ri_caller}: forwarded arguments remain after implicit variable-list parsing; use -- before the variable names." >&2
        fi
    fi

    if [[ -z "${__hs_processed[state]-}" ]]; then
        echo "[ERROR] ${__hs_ri_caller}: state variable is uninitialized; missing required -S <statevar> option." >&2
        return "$HS_ERR_STATE_VAR_UNINITIALIZED"
    fi
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

# _hs_hs2_build <existing_payload> [record ...]
# Builds an HS2 state string from existing payload and new records and prints
# it to stdout. Callers are responsible for assigning the result.
_hs_hs2_build() {
    local __hs2b_payload="$1"
    shift 1
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
    printf 'HS2:%s:%s' "$__hs2b_cksum" "$__hs2b_payload"
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
