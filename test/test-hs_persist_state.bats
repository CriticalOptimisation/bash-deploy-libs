#!/usr/bin/env bats

# Bats tests for handle_state.sh
# Run with: bats test/test-hs_persist_state.bats

setup_file() {
  bats_require_minimum_version 1.5.0
  export LIB="$BATS_TEST_DIRNAME/../config/handle_state.sh"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
  export BATS_TEST_TMPDIR
  # 2 s covers setup + any legitimate test in this file; the failure mode this
  # guards against is the --list-reserved re-entry fork bomb (issue #136),
  # which otherwise burns ~15 s per test saturating the fork budget.
  export BATS_TEST_TIMEOUT=2
}
setup() {
  # `builtin source` bypasses any test-installed override of `source` (the
  # dependency-check tests at the end of this file replace `source` with a
  # fault-injector).  Surface load failures with a dedicated exit code and a
  # diagnostic line so the bats log identifies *why* setup aborted, instead
  # of the generic "$status == 1" a bare failed source would yield.
  # shellcheck source=../config/handle_state.sh
  if ! builtin source "$LIB"; then
    echo "[BATS setup] failed to load $LIB" >&2
    return 2
  fi
}

# Helper: return a non-HS2 string for corrupt-state tests.
hs2_corrupt_state() {
  printf 'NOTHS2:invalid'
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects caller that declared __hs_remaining as a non-array" {
  # shellcheck disable=SC2329
  f() {
    # shellcheck disable=SC2178
    local __hs_remaining=""
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state foo
  }
  run -"$HS_ERR_INVALID_ARGUMENT_TYPE" --separate-stderr f
  [[ "$stderr" == *"__hs_remaining"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects caller that declared __hs_processed as a non-associative array" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -a __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state foo
  }
  run -"$HS_ERR_INVALID_ARGUMENT_TYPE" --separate-stderr f
  [[ "$stderr" == *"__hs_processed"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs parses known options and preserves remaining arguments" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: bad -q -S state -- foo bar
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_processed[quiet]}" "${__hs_remaining[*]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|bad" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts trailing variable names into processed vars" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: bad -q -S state -- foo bar
    printf "%s|%s|%s|%s" "${__hs_processed[state]}" "${__hs_processed[quiet]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|bad|foo bar " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves explicit variable order in processed vars" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state -- alpha beta gamma
    printf "%s" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "alpha beta gamma " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves trailing variable order without explicit separator" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -q -S state alpha beta gamma
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_processed[quiet]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|alpha beta gamma" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs treats only the last separator as explicit variable-list start" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state -- alpha -- beta
    printf "%s|%s" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "-- alpha|beta " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts explicit vars after a trailing separator even with prior words" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state 1 -- alpha beta
    printf "%s|%s" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "1|alpha beta " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves trailing vars after unknown option and parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state -b alpha beta
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b|alpha beta" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs allows forwarded unknown option parameters before trailing vars" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state -c 1 -b beta gamma
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-c 1 -b|beta gamma" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a missing -S option" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -q foo
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects an invalid -S variable name" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S 1invalid foo
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid'"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects -S without a parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: bad -S
  }
  run -"$HS_ERR_MISSING_ARGUMENT" --separate-stderr f
  [[ "$stderr" == *"missing required parameter to option -S"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves an unknown short option without parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper S: -a -S state foo
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-a|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves an unknown short option and its parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper S: -b toto -S state foo
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b toto|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts vars after unknown forwarded options" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper S: -b toto -S state foo bar
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b toto|foo bar" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves forwarded bare words outside the vars list" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper S: -S state 1invalid foo
    printf "%s|%s|%s" "${__hs_processed[state]}" "${__hs_remaining[*]}" "${__hs_processed[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|1invalid|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs,hs_persist_state
@test "hs_persist_state rejects variable names starting with the __hs_ reserved prefix" {
  # shellcheck disable=SC2329
  f() {
    # shellcheck disable=SC2178
    local __hs_remaining="some_value"
    local state=""
    hs_persist_state -S state -- __hs_remaining
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# ---------------------------------------------------------------------------
# hs_read_persisted_state

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on undeclared restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local abar=v2; hs_persist_state -S "$1" -- abar || return $?; }
    local state=""
    init state || return $?
    # bar is not declared as local in f — must error, not silently create a global
    hs_read_persisted_state -S state -- abar
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"is not declared in scope"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on pre-set restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local baz=new; hs_persist_state -S "$1" -- baz || return $?; }
    local state=""
    init state || return $?
    local baz=old
    # baz is declared local and set — must error, not silently overwrite
    hs_read_persisted_state -S state -- baz
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on empty-string restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local baz=new; hs_persist_state -S "$1" -- baz || return $?; }
    local state=""
    init state || return $?
    local baz=""
    # baz is set to empty string — still set, must error
    hs_read_persisted_state -S state -- baz
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on pre-set indexed array restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local -a arr=(one two); hs_persist_state -S "$1" -- arr || return $?; }
    local state=""
    init state || return $?
    local -a arr=(existing)
    hs_read_persisted_state -S state -- arr
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on empty indexed array restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local -a arr=(one); hs_persist_state -S "$1" -- arr || return $?; }
    local state=""
    init state || return $?
    local -a arr=()
    : "${arr[@]}"  # avoids 'variable appears unused' linter error
    # arr=() counts as set — must error, not silently overwrite
    hs_read_persisted_state -S state -- arr
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on pre-set associative array restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local -A amap=([k]=v); hs_persist_state -S "$1" -- amap || return $?; }
    local state=""
    init state || return $?
    local -A amap=([old]=val)
    hs_read_persisted_state -S state -- amap
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on empty associative array restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local -A amap=([k]=v); hs_persist_state -S "$1" -- amap || return $?; }
    local state=""
    init state || return $?
    local -A amap=()
    # amap=() counts as set — must error, not silently overwrite
    hs_read_persisted_state -S state -- amap
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on pre-set nameref restore target" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local -A target=([x]=1)
      local -n ref=target
      hs_persist_state -S "$1" -- target ref || return $?
    }
    local state=""
    init state || return $?
    local -A target
    local -n ref=target
    # ref already points to target — must error, not silently overwrite
    hs_read_persisted_state -S state -- ref
  }
  run -"$HS_ERR_VAR_ALREADY_SET" --separate-stderr f
  [[ "$stderr" == *"is already set"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state restores explicitly listed unset locals" {
  # shellcheck disable=SC2329
  f() {
    init()    { local foo=secret ebar=v2 baz=new; : "$ebar"; hs_persist_state -S "$1" -- foo ebar baz || return $?; }
    cleanup() { local foo ebar baz; hs_read_persisted_state -S "$1" -- foo ebar baz || return $?; printf "%s:%s:%s" "$foo" "$ebar" "$baz"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 f
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit restore is not affected by ancestor locals with internal names" {
  # Regression: if an ancestor frame declares a local named list_reserved,
  # hs_read_persisted_state must not be fooled into skipping its normal
  # processing path. The behaviour must be identical to the baseline above.
  # shellcheck disable=SC2329
  f() {
    local list_reserved=1  # ancestor local with a value — must be invisible to the library
    init()    { local foo=secret ebar=v2 baz=new; : "$ebar"; hs_persist_state -S "$1" -- foo ebar baz || return $?; }
    cleanup() { local foo ebar baz; hs_read_persisted_state -S "$1" -- foo ebar baz || return $?; printf "%s:%s:%s" "$foo" "$ebar" "$baz"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:v2:new" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state -q does not suppress guard errors" {
  # shellcheck disable=SC2329
  f() {
    init() { local abar=v2; : "$abar"; hs_persist_state -S "$1" -- abar || return $?; }
    local state=""
    init state || return $?
    # -q suppresses missing-variable warnings but must not suppress guard errors
    hs_read_persisted_state -q -S state -- abar
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"is not declared in scope"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state all-or-nothing: does not restore any var when a later var fails" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=a abar=b; : "$abar"; hs_persist_state -S "$1" -- foo abar || return $?; }
    local state=""
    init state || return $?
    local foo
    # bar is not declared — validation must fail before any restoration occurs
    local err=0
    hs_read_persisted_state -S state -- foo abar || err=$?
    # foo must remain unset: all-or-nothing means no partial restoration
    printf "%s" "${foo:-UNSET}"
    return "$err"
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'abar' is not declared in scope"* ]]
  [ "$output" = "UNSET" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form targets unset var in ancestor scope" {
  # shellcheck disable=SC2329
  init()   { local outer_var=from_init; hs_persist_state -S "$1" -- outer_var || return $?; }
  # shellcheck disable=SC2329
  inner()  { hs_read_persisted_state -S "$1" -- outer_var || return $?; }
  # shellcheck disable=SC2329
  middle() { local outer_var; inner "$1" || return $?; printf "%s" "$outer_var"; }
  # shellcheck disable=SC2329
  f() {
    local state=""
    init state || return $?
    middle state
  }
  run -0 --separate-stderr f
  [ "$output" = "from_init" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "eval the output of hs_read_persisted_state in caller scope restores values" {
  # shellcheck disable=SC2329
  f() {
    init()    { local foo=secret obar=v2 baz=new; hs_persist_state -S "$1" -- foo obar baz || return $?; }
    cleanup() { local state="$1"; local foo obar baz; eval "$(hs_read_persisted_state -S state)" || return $?; printf "%s:%s:%s" "$foo" "$obar" "$baz"; }
    local state=""
    init state || return $?
    cleanup "$state"
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:v2:new" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state accepts explicit -S state and emits an HS2 probe snippet" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    local state=""
    init state || return $?
    printf "%s" "$(hs_read_persisted_state -S state)"
  }
  run -0 --separate-stderr f
  [[ "$output" == *'hs_read_persisted_state -q -S state --'* ]]
  [[ "$output" == *'local -p | while IFS= read -r __hs_local_decl; do'* ]]
  [[ "$output" == *') >/dev/null'* ]]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state restores only requested variables" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret obar=v2 obaz=new; hs_persist_state -S "$1" -- foo obar obaz || return $?; }
    cleanup(){
      local state_var="$1"
      local foo obar obaz
      hs_read_persisted_state -S "$state_var" -- foo obaz || return $?
      printf "%s:%s:%s" "$foo" "${obar:-}" "$obaz"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "secret::new" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state with explicit -- and no variable names emits no probe snippet" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    local state=""
    init state || return $?
    hs_read_persisted_state -S state --
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state only auto-restores locals in the immediate caller scope" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    outer(){
      local foo
      inner_auto
      printf "%s:" "$foo"
      unset foo
      inner_explicit
      printf "%s" "$foo"
    }
    inner_auto(){
      eval "$(hs_read_persisted_state -S state)"
    }
    inner_explicit(){
      hs_read_persisted_state -S state -- foo
    }
    local state=""
    init state || return $?
    outer
  }
  run -0 --separate-stderr f
  [ "$output" = ":secret" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state warns when a requested variable is not in state" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    cleanup(){
      local state_var="$1"
      local foo ibar
      hs_read_persisted_state -S "$state_var" -- foo ibar || return $?
      printf "%s:%s" "$foo" "${ibar:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'ibar' is not defined in the state."* ]]
  [ "$output" = "secret:" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state warns for each missing requested variable" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    cleanup(){
      local state_var="$1"
      local foo bar ibaz
      hs_read_persisted_state -S "$state_var" -- foo bar ibaz || return $?
      printf "%s:%s:%s" "$foo" "${bar:-}" "${ibaz:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'bar' is not defined in the state."* ]]
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'ibaz' is not defined in the state."* ]]
  [ "$output" = "secret::" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state -q silences warnings for variables not in state" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    cleanup(){
      local state_var="$1"
      local foo bar
      hs_read_persisted_state -q -S "$state_var" -- foo bar || return $?
      printf "%s:%s" "$foo" "${bar:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state accepts -q after -S state" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    cleanup(){
      local state_var="$1"
      local foo bar
      hs_read_persisted_state -S "$state_var" -q -- foo bar || return $?
      printf "%s:%s" "$foo" "${bar:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects a missing state variable name" {
  # shellcheck disable=SC2329
  f() { hs_read_persisted_state >/dev/null; }
  run -"$HS_ERR_MISSING_ARGUMENT" --separate-stderr f
  [[ "$stderr" == *"missing required parameter to option -S"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects an invalid state variable name" {
  # shellcheck disable=SC2329
  f() { hs_read_persisted_state -S "1invalid-var-name" >/dev/null; }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects an unset or empty state variable" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    hs_read_persisted_state -S state >/dev/null
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"state variable 'state' is not set or is empty"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects corrupt (non-HS2) state in explicit restore path" {
  # shellcheck disable=SC2329
  f() {
    local state
    state="$(hs2_corrupt_state)"
    local foo
    hs_read_persisted_state -S state -- foo
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"is not in HS2 format"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects corrupt (non-HS2) state in implicit restore path" {
  # shellcheck disable=SC2329
  f() {
    local state
    state="$(hs2_corrupt_state)"
    # Capture separately so the exit code is not swallowed by $().
    local snippet
    snippet="$(hs_read_persisted_state -S state)" || return $?
    printf "%s" "$snippet"
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"is not in HS2 format"* ]]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Grandparent and global explicit restore

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form targets unset indexed array in ancestor scope" {
  # shellcheck disable=SC2329
  init()   { local -a items=(one two "three four"); hs_persist_state -S "$1" -- items || return $?; }
  # shellcheck disable=SC2329
  inner()  { hs_read_persisted_state -S "$1" -- items || return $?; }
  # shellcheck disable=SC2329
  middle() {
    local -a items
    inner "$1" || return $?
    printf "%s:%s:%s" "${items[0]-}" "${items[1]-}" "${items[2]-}"
  }
  # shellcheck disable=SC2329
  f() {
    local state=""
    init state || return $?
    middle state
  }
  run -0 --separate-stderr f
  [ "$output" = "one:two:three four" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form restores nameref and target in ancestor scope" {
  # shellcheck disable=SC2329
  init()   {
    local -A target=([hp]=100 [name]="Shepard")
    local -n ref=target
    hs_persist_state -S "$1" -- target ref || return $?
  }
  inner()  { hs_read_persisted_state -S "$1" -- target ref || return $?; }
  middle() {
    local -A target
    local -n ref
    inner "$1" || return $?
    printf "%s:%s" "${ref[name]-}" "${ref[hp]-}"
  }
  # shellcheck disable=SC2329
  f() {
    local state=""
    init state || return $?
    middle state
  }
  run -0 --separate-stderr f
  [ "$output" = "Shepard:100" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form restores nameref and target in direct caller frame" {
  # shellcheck disable=SC2329
  init() {
    local -A target=([hp]=100 [name]="Shepard")
    local -n ref=target
    hs_persist_state -S "$1" -- target ref || return $?
  }
  cleanup() {
    local -A target
    local -n ref
    hs_read_persisted_state -S "$1" -- target ref || return $?
    printf "%s:%s" "${ref[name]-}" "${ref[hp]-}"
  }
  # shellcheck disable=SC2329
  f() {
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "Shepard:100" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form restores scalar to a declare -g global" {
  # shellcheck disable=SC2329
  f() {
    init()    { local gvar=global_val; hs_persist_state -S "$1" -- gvar || return $?; }
    cleanup() {
      declare -g gvar
      hs_read_persisted_state -S "$1" -- gvar || return $?
      printf "%s" "${gvar:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "global_val" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form restores indexed array to a declare -g global" {
  # shellcheck disable=SC2329
  f() {
    init()    { local -a items=(alpha beta); hs_persist_state -S "$1" -- items || return $?; }
    cleanup() {
      declare -ga items
      hs_read_persisted_state -S "$1" -- items || return $?
      printf "%s:%s" "${items[0]-}" "${items[1]-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "alpha:beta" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form restores nameref and target to declare -g globals" {
  # shellcheck disable=SC2329
  f() {
    init()    {
      local -A target=([hp]=200 [name]="Wrex")
      local -n ref=target
      hs_persist_state -S "$1" -- target ref || return $?
    }
    cleanup() {
      declare -gA target
      declare -gn ref
      : "${target[@]}"  # avoid 'variable appears unused' linter error
      hs_read_persisted_state -S "$1" -- target ref || return $?
      printf "%s:%s" "${ref[name]-}" "${ref[hp]-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "Wrex:200" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "design: implicit restore (eval form) only targets the immediate caller's unset locals" {
  # shellcheck disable=SC2329
  # The eval form probes inner()'s own locals via local -p; it cannot see
  # outer_var declared in f(). This is the intended behaviour: the eval snippet
  # is self-contained to the caller that evaluates it.
  f() {
    init()  { local outer_var=from_init; hs_persist_state -S "$1" -- outer_var || return $?; }
    inner() { eval "$(hs_read_persisted_state -S "$1")" || return $?; }
    local outer_var
    local state=""
    init state || return $?
    inner state || return $?
    printf "%s" "${outer_var:-NOT_RESTORED}"
  }
  run -0 --separate-stderr f
  [ "$output" = "NOT_RESTORED" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "design: implicit restore (eval form) intentionally ignores declare -g globals" {
  # shellcheck disable=SC2329
  # local -p lists only function-local variables, not globals declared with
  # declare -g. A library must not randomly overwrite application globals, so
  # this scope restriction is a deliberate safety property, not a limitation.
  f() {
    init()    { local gvar=global_val; hs_persist_state -S "$1" -- gvar || return $?; }
    cleanup() {
      declare -g gvar
      eval "$(hs_read_persisted_state -S "$1")" || return $?
      printf "%s" "${gvar:-NOT_RESTORED}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "NOT_RESTORED" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state implicit form restores __hs_-prefixed locals not in --list-reserved" {
  # The eval snippet must not silently skip __hs_* names. Filtering them out
  # turns future API breaks (e.g. an expansion of the reserved list) into silent
  # data loss. Any name hs_persist_state accepted must be implicitly restorable.
  # Uses separate persist/restore scopes so that the local is genuinely unset
  # when eval runs (avoiding the same-scope-local issue that is the root cause
  # of the failure in "hs_persist_state accepts __hs_-prefixed names not in
  # --list-reserved").
  # shellcheck disable=SC2329
  f() {
    persist()  { local __hs_custom_lib_var="hello"; hs_persist_state -S "$1" -- __hs_custom_lib_var || return $?; }
    restore()  { local __hs_custom_lib_var; eval "$(hs_read_persisted_state -S "$1")" || return $?; printf '%s' "$__hs_custom_lib_var"; }
    local state=""
    persist state || return $?
    restore state
  }
  run -0 --separate-stderr f
  [ "$output" = "hello" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state implicit form fails when caller has a reserved name declared local" {
  # The implicit snippet must not silently skip a reserved name found in the
  # caller's local frame. Silent skip masks a programming error and could cause
  # data loss if the reserved list expands in a future API version.
  # shellcheck disable=SC2329
  f() {
    init()    { local token="abc"; hs_persist_state -S "$1" -- token || return $?; }
    cleanup() {
      local __hs_remaining
      local token
      eval "$(hs_read_persisted_state -S "$1")" || return $?
      printf '%s' "$token"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a repeated -S option" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S var1 -S var2
  }
  run -"$HS_ERR_MULTIPLE_STATE_INPUTS" --separate-stderr f
  [[ "$stderr" == *"-S"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects an identically repeated -S option" {
  # shellcheck disable=SC2329
  f() {
    local -a __hs_remaining=()
    local -A __hs_processed=()
    _hs_resolve_state_inputs my_helper qS: -S state -S state
  }
  run -"$HS_ERR_MULTIPLE_STATE_INPUTS" --separate-stderr f
  [[ "$stderr" == *"-S"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects adjacent repeated -S options" {
  # shellcheck disable=SC2329
  f() {
    local state1="" state2=""
    local myvar="hello"
    : "$myvar"
    hs_persist_state -S state1 -S state2 -- myvar
  }
  run -"$HS_ERR_MULTIPLE_STATE_INPUTS" --separate-stderr f
  [[ "$stderr" == *"-S"* ]]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects repeated -S options spaced by a non-option word" {
  # shellcheck disable=SC2329
  f() {
    local state1="" state2=""
    hs_destroy_state -S state1 extra_arg -S state2 -- myvar
  }
  run -"$HS_ERR_MULTIPLE_STATE_INPUTS" --separate-stderr f
  [[ "$stderr" == *"-S"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects repeated -S options spaced by -q" {
  # shellcheck disable=SC2329
  f() {
    local state1="" state2=""
    : "$state1" "$state2"
    hs_read_persisted_state -S state1 -q -S state2
  }
  run -"$HS_ERR_MULTIPLE_STATE_INPUTS" --separate-stderr f
  [[ "$stderr" == *"-S"* ]]
}

# ---------------------------------------------------------------------------
# hs_persist_state

# bats test_tags=hs_persist_state
@test "hs_persist_state produces an HS2-format state string" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    local scalar="value"
    : "$scalar"   # avoid 'variable appears unused' linter error
    hs_persist_state -S state -- scalar || return $?
    [[ "$state" == HS2:* ]] || { printf "state does not start with HS2: got '%s'\n" "$state" >&2; return 1; }
  }
  run -0 --separate-stderr f
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state round-trips an indexed array via explicit restore" {
  # shellcheck disable=SC2329
  f() {
    init()    { local -a items=(one two "three four"); hs_persist_state -S "$1" -- items || return $?; }
    cleanup() { local -a items; hs_read_persisted_state -S "$1" -- items || return $?
                printf "%s:%s:%s" "${items[0]-}" "${items[1]-}" "${items[2]-}"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "one:two:three four" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state round-trips an associative array via explicit restore" {
  # shellcheck disable=SC2329
  f() {
    init()    { local -A amap=([key]=value [other]="spaced value"); hs_persist_state -S "$1" -- amap || return $?; }
    cleanup() { local -A amap; hs_read_persisted_state -S "$1" -- amap || return $?
                printf "%s:%s" "${amap[key]-}" "${amap[other]-}"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "value:spaced value" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state round-trips a nameref with co-persisted target via eval restore" {
  # shellcheck disable=SC2329
  # An unset declared nameref (local -n active) is set by the eval snippet just
  # like any other unset local — the snippet emits "declare -n active=commander"
  # which binds the nameref. No special handling is required in the caller.
  f() {
    init() {
      local -A commander=([hp]=100 [name]="Shepard")
      local -n active=commander
      hs_persist_state -S "$1" -- commander active || return $?
    }
    cleanup() {
      local -A commander
      local -n active
      : "$commander"  # avoid 'variable appears unused' linter error
      eval "$(hs_read_persisted_state -S "$1")" || return $?
      printf "%s:%s" "${active[name]-}" "${active[hp]-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "Shepard:100" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects a nameref whose target is not being persisted" {
  # shellcheck disable=SC2329
  f() {
    local str_target="value"
    local -n ref=str_target
    local state=""
    : "$str_target"  # avoids 'variable appears unused' linter error
    hs_persist_state -S state -- ref || return $?
  }
  run -"$HS_ERR_NAMEREF_TARGET_NOT_PERSISTED" --separate-stderr f
  [ -z "$output" ]
  [[ "$stderr" == *"ref"* ]]
  [[ "$stderr" == *"str_target"* ]]
}

# bats test_tags=hs_persist_state,hs_extract_token,hs_finalize_token,hs_destroy_state,issue-136,issue-143
@test "read-modify-write — entry point updates one variable in an existing state token" {
  # Full read/modify/write cycle using the hs_extract_token / hs_finalize_token
  # entry-point pattern.  The test verifies that:
  #   1. init persists two vars (counter, label).
  #   2. update_counter uses hs_extract_token + hs_destroy_state + hs_persist_state
  #      + hs_finalize_token to increment counter without touching label.
  #   3. read_back restores both vars and confirms the update landed correctly.
  # hs_destroy_state is required before re-persisting because hs_persist_state
  # rejects names already present in the token (HS_ERR_VAR_NAME_COLLISION).
  # Because Bash is sequential and subshells cannot write back to the parent
  # shell's variables, the token update is safe: hs_finalize_token runs in a
  # subshell only to emit the assignment code; eval in the entry-point frame
  # performs the actual write atomically.
  # shellcheck disable=SC2329
  f() {
    init() {
      local counter=0 label="start"
      hs_persist_state -S "$1" -- counter label || return $?
    }
    update_counter() {
      # Canonical skeleton: extract -> body-unless-listing -> finalize.
      eval "$(hs_extract_token update_counter __uc_tok "$@")" || return $?
      hs_is_list_reserved_mode -S __uc_tok || { _update_counter_body "$@" || return $?; }
      eval "$(hs_finalize_token update_counter __uc_tok "$@")" || return $?
    }
    _update_counter_body() {
      local counter label
      hs_read_persisted_state -S __uc_tok -- counter label || return $?
      (( counter++ )) || true
      # Destroy before re-persisting to avoid HS_ERR_VAR_NAME_COLLISION.
      hs_destroy_state -S __uc_tok -- counter label || return $?
      hs_persist_state  -S __uc_tok -- counter label || return $?
    }
    read_back() {
      local counter label
      hs_read_persisted_state -S "$1" -- counter label || return $?
      printf "%s:%s" "$counter" "$label"
    }
    local state=""
    init state || return $?
    update_counter -S state || return $?
    read_back state
  }
  run -0 --separate-stderr f
  [ "$output" = "1:start" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state reports a collision for a variable already in state" {
  # shellcheck disable=SC2329
  f() {
    init_existing() { local foo=one bar=two; hs_persist_state -S "$1" -- foo bar || return $?; }
    init_again()    { local foo=three bar=four baz=five; hs_persist_state -S "$1" -- foo bar baz || return $?; }
    local state=""
    init_existing state || return $?
    init_again state
  }
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr f
  [[ "$stderr" == *"already exists in the state"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state detects collision when prior state has the variable" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    init_first()  { local foo=""; hs_persist_state -S "$1" -- foo || return $?; }
    init_second() { local foo=three; hs_persist_state -S "$1" -- foo || return $?; }
    init_first state || return $?
    init_second state
  }
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr f
  [[ "$stderr" == *"already exists in the state"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state persists a set variable and skips a declared-but-unset one" {
  # shellcheck disable=SC2329
  f() {
    local state_var=""
    init()    { local foo=one unset_var; hs_persist_state "$@" -- foo unset_var || return $?; }
    cleanup() { local foo unset_var; hs_read_persisted_state -q "$@" -- foo unset_var || return $?; printf "%s:%s" "$foo" "${unset_var:-}"; }
    init -S state_var || return $?
    cleanup -S state_var
  }
  run -0 --separate-stderr f
  [ "$output" = "one:" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state errors on a variable name not declared in scope" {
  # shellcheck disable=SC2329
  f() {
    local state_var=""
    init(){ hs_persist_state "$@" -- not_a_var || return $?; }
    init -S state_var
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'not_a_var' is not declared in scope"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects a function name with HS_ERR_UNKNOWN_VAR_NAME" {
  # shellcheck disable=SC2329
  f() {
    my_func(){ echo "nope"; }
    local state_var=""
    hs_persist_state -S state_var -- my_func || return $?
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [ -z "$output" ]
  [[ "$stderr" == *"is a function, not a variable"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects a function name even when mixed with valid variables" {
  # shellcheck disable=SC2329
  f() {
    my_func(){ echo "nope"; }
    local good_var="kept"
    local state_var=""
    : "$good_var"
    hs_persist_state -S state_var -- good_var my_func || return $?
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [ -z "$output" ]
  [[ "$stderr" == *"is a function, not a variable"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state preserves special characters in persisted values" {
  # shellcheck disable=SC2329
  f() {
    init()    { local foo="a b \"c\" \$d"; hs_persist_state "$@" -- foo || return $?; }
    cleanup() { local foo; hs_read_persisted_state "$@" -- foo || return $?; printf "%s" "$foo"; }
    local state=""
    init -S state || return $?
    cleanup -S state
  }
  run -0 f
  [ "$output" = "a b \"c\" \$d" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state with -S detects an invalid variable name" {
  # shellcheck disable=SC2329
  f() { hs_persist_state -S "1invalid-var-name" -- foo; }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state ignores forwarded args before final --" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=two; hs_persist_state bad -S "$1" -- foo || return $?; }
    local state=""
    init state || return $?
    cleanup() { local foo; hs_read_persisted_state -S "$1" -- foo || return $?; printf "%s" "$foo"; }
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects an invalid variable name in the persist list" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    init() { local foo=two; hs_persist_state -S "$1" -- "1invalid-var-name" foo || return $?; }
    init state
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state requires -S" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=two bar=three; hs_persist_state -- foo bar || return $?; }
    init
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state --list-reserved names are all rejected as persisted variable names" {
  # shellcheck disable=SC2329
  f() {
    local state name
    while IFS= read -r name; do
      state=""
      hs_persist_state -S state -- "$name" || return $?
    done < <(hs_persist_state --list-reserved)
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state accepts __hs_-prefixed names not in --list-reserved" {
  # The reserved check must only reject names that are actually in the
  # collision section (__hs_remaining, __hs_processed), not every __hs_* name.
  # shellcheck disable=SC2329
  f() {
    init()    { local __hs_custom_lib_var="hello"; hs_persist_state -S "$1" -- __hs_custom_lib_var || return $?; }
    cleanup() { local __hs_custom_lib_var; hs_read_persisted_state -S "$1" -- __hs_custom_lib_var || return $?; printf '%s' "$__hs_custom_lib_var"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "hello" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state with -S var_name assigns state to variable" {
  # shellcheck disable=SC2329
  f() {
    local encoded=""
    init()    { local bar=two; hs_persist_state -S "$1" -- bar || return $?; }
    cleanup() { local bar; hs_read_persisted_state -S "$1" -- bar || return $?; printf "%s" "$bar"; }
    : "$encoded"  # avoids 'variable appears unused linter error'
    init encoded || return $?
    cleanup encoded
  }
  run -0 f
  [ "$output" = "two" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects every reserved name as the -S state variable" {
  # Each name in --list-reserved is also a local in the entry-point frame.
  # Passing it as -S would shadow the caller's variable so the updated state
  # would be discarded silently. _hs_resolve_state_inputs must reject every
  # reserved name with HS_ERR_RESERVED_VAR_NAME, not just the first one.
  # shellcheck disable=SC2329
  f() {
    local foo=one name rc
    while IFS= read -r name; do
      hs_persist_state -S "$name" -- foo; rc=$?
      [[ $rc -eq "$HS_ERR_RESERVED_VAR_NAME" ]] || return "$rc"
    done < <(hs_persist_state --list-reserved)
    return "$HS_ERR_RESERVED_VAR_NAME"
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects every reserved name as the -S state variable" {
  # shellcheck disable=SC2329
  f() {
    local name rc
    while IFS= read -r name; do
      hs_destroy_state -S "$name" -- foo; rc=$?
      [[ $rc -eq "$HS_ERR_RESERVED_VAR_NAME" ]] || return "$rc"
    done < <(hs_destroy_state --list-reserved)
    return "$HS_ERR_RESERVED_VAR_NAME"
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state rejects every reserved name as the -S state variable" {
  # shellcheck disable=SC2329
  f() {
    local name rc
    while IFS= read -r name; do
      hs_read_persisted_state -S "$name" -- foo; rc=$?
      [[ $rc -eq "$HS_ERR_RESERVED_VAR_NAME" ]] || return "$rc"
    done < <(hs_read_persisted_state --list-reserved)
    return "$HS_ERR_RESERVED_VAR_NAME"
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state rejects corrupt (non-HS2) prior state" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=two; hs_persist_state "$@" -- foo || return $?; }
    local state_var
    state_var="$(hs2_corrupt_state)"
    init -S state_var
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"existing state is not in HS2 format"* ]]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# hs_destroy_state

# bats test_tags=hs_destroy_state
@test "hs_destroy_state with -S rewrites the named variable in place" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    init() { local foo=one bar=two; hs_persist_state -S "$1" -- foo bar || return $?; }
    init state || return $?
    hs_destroy_state -S state -- foo || return $?
    cleanup() {
      local bar
      hs_read_persisted_state -S "$1" -- bar || return $?
      printf "%s" "${bar:-}"
    }
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state requires -S" {
  # shellcheck disable=SC2329
  f() { hs_destroy_state -- foo bar >/dev/null; }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects invalid destroy variable names" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    local foo=one
    hs_persist_state -S state -- foo || return $?
    hs_destroy_state -S state -- "1invalid-var-name" >/dev/null
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state ignores a forwarded arg immediately before final --" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    init() { local foo=one bar=two; hs_persist_state -S "$1" -- foo bar || return $?; }
    init state || return $?
    hs_destroy_state -S state bad -- foo || return $?
    cleanup() {
      local bar
      hs_read_persisted_state -S "$1" -- bar || return $?
      printf "%s" "${bar:-}"
    }
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state ignores a forwarded arg before the options" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    init() { local foo=one bar=two; hs_persist_state -S "$1" -- foo bar || return $?; }
    init state || return $?
    hs_destroy_state bad -S state -- foo || return $?
    cleanup() {
      local bar
      hs_read_persisted_state -S "$1" -- bar || return $?
      printf "%s" "${bar:-}"
    }
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state fails when asked to remove a variable not present in the state" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=one; hs_persist_state -S "$1" -- foo || return $?; }
    local state=""
    init state || return $?
    hs_destroy_state -S state -- missing >/dev/null
  }
  run -"$HS_ERR_VAR_NAME_NOT_IN_STATE" --separate-stderr f
  [[ "$stderr" == *"variable 'missing' is not defined in the state"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state detects corrupt (non-HS2) prior state" {
  # shellcheck disable=SC2329
  f() {
    local state
    state="$(hs2_corrupt_state)"
    hs_destroy_state -S state -- foo >/dev/null
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"is not in HS2 format"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects a state variable named with a reserved identifier" {
  # __hs_processed is declared local -A in hs_destroy_state's entry-point frame.
  # When the caller passes -S __hs_processed, that local shadows the caller's
  # variable: reads see an empty value instead of the HS2 string, and any write
  # is discarded into the local array instead of the caller's variable.
  # The library must detect this early and return HS_ERR_RESERVED_VAR_NAME
  # rather than the confusing HS_ERR_CORRUPT_STATE currently produced.
  # shellcheck disable=SC2329
  f() {
    local temp=""
    init() { local foo=one bar=two; hs_persist_state -S "$1" -- foo bar || return $?; }
    init temp || return $?
    # shellcheck disable=SC2178
    local __hs_processed="$temp"
    hs_destroy_state -S __hs_processed -- foo
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"reserved"* ]]
}

# ---------------------------------------------------------------------------
# --list-reserved

# bats test_tags=hs_persist_state
@test "hs_persist_state --list-reserved returns 0 with non-empty output" {
  run -0 hs_persist_state --list-reserved
  [[ -n "$output" ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state --list-reserved output names all start with __hs_" {
  local name count=0
  while IFS= read -r name; do
    (( ++count ))
    [[ "$name" == __hs_* ]] || { printf 'unexpected name: %s\n' "$name" >&2; return 1; }
  done < <(hs_persist_state --list-reserved)
  [[ "$count" -ge 1 ]]  # guards against vacuous pass when --list-reserved is broken
}

# bats test_tags=hs_persist_state,hs_read_persisted_state,hs_destroy_state
@test "--list-reserved produces identical output from all three API entry points" {
  # run -0 also pins the exit status and non-emptiness: with bare command
  # substitutions a broken --list-reserved would compare empty == empty.
  local out_persist out_read out_destroy
  run -0 hs_persist_state --list-reserved
  [[ -n "$output" ]]
  out_persist="$output"
  run -0 hs_read_persisted_state --list-reserved
  out_read="$output"
  run -0 hs_destroy_state --list-reserved
  out_destroy="$output"
  [[ "$out_persist" == "$out_read" ]]
  [[ "$out_persist" == "$out_destroy" ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state --list-reserved returns 0 with non-empty output" {
  run -0 hs_read_persisted_state --list-reserved
  [[ -n "$output" ]]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state --list-reserved returns 0 with non-empty output" {
  run -0 hs_destroy_state --list-reserved
  [[ -n "$output" ]]
}

# bats test_tags=hs_persist_state,hs_read_persisted_state,hs_destroy_state
@test "--list-reserved collision-surface size is within the expected threshold" {
  local name count=0
  while IFS= read -r name; do
    (( ++count ))
    # Regression guard inside the loop: the process substitution streams into
    # read in parallel, so an endless-output regression would otherwise spin
    # here until the test timeout.  Target is exactly 2 names
    # (__hs_remaining, __hs_processed).
    [[ "$count" -le 2 ]] || {
      printf 'more than 2 reserved names reported: runaway or grown --list-reserved output\n' >&2
      return 1
    }
  done < <(hs_persist_state --list-reserved)
  [[ "$count" -ge 1 ]]  # guards against vacuous pass when --list-reserved is broken
}

# ---------------------------------------------------------------------------
# Library load-time dependency checks
# ---------------------------------------------------------------------------

# bats test_tags=handle_state,dependency
@test "handle_state.sh: source fails with HS_ERR_DEPENDENCY_MISSING when command_guard.sh cannot be loaded" {
  # Overload `source` in a fresh child shell so that handle_state.sh's internal
  # load of command_guard.sh fails as if the file were missing or broken; every
  # other source call (including the outer load of $LIB) delegates to the real
  # builtin so the body of handle_state.sh actually runs and reaches the
  # dependency check.  The script is written to a file rather than piped
  # because bats `run` wraps its argument in a command substitution and stdin
  # propagation through that wrapper is brittle.
  local script="$BATS_TEST_TMPDIR/source_override.sh"
  cat > "$script" <<'OVERRIDE'
source() {
    if [[ "${1##*/}" == 'command_guard.sh' ]]; then
        echo 'mock: command_guard.sh cannot be loaded' >&2
        return 127
    fi
    builtin source "$@"
}
OVERRIDE
  # Append the call that triggers the partial load (interpolates outer $LIB).
  printf 'source %q\n' "$LIB" >> "$script"

  run -"$HS_ERR_DEPENDENCY_MISSING" --separate-stderr bash --noprofile --norc "$script"
  [[ "$stderr" == *"handle_state.sh"* ]]
  [[ "$stderr" == *"command_guard.sh"* ]]
  [[ "$stderr" == *"Unable to load"* ]]
}

# bats test_tags=handle_state,dependency
@test "handle_state.sh: source returns cg_guard exit code when cg_guard reports a missing command" {
  # Pre-source command_guard.sh so its sentinel is set (handle_state.sh's
  # `source command_guard.sh` then becomes a no-op).  Override cg_guard so the
  # subsequent `cg_guard cksum || return $?` propagates CG_ERR_NOT_FOUND.  The
  # current handler is intentionally a one-liner without a diagnostic; the
  # contract this test pins is "the cg error code reaches the caller verbatim".
  local script="$BATS_TEST_TMPDIR/cg_guard_override.sh"
  cat > "$script" <<EOF
builtin source $(printf %q "${LIB%/*}/command_guard.sh")
cg_guard() { return "\$CG_ERR_NOT_FOUND"; }
builtin source $(printf %q "$LIB")
EOF
  run -"$CG_ERR_NOT_FOUND" bash --noprofile --norc "$script"
}

# ---------------------------------------------------------------------------
# hs_extract_token
# ---------------------------------------------------------------------------

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — extracts token value into named local" {
  local my_token="HS2:test:payload"
  f() {
    eval "$(hs_extract_token f __et_tok "$@")" || return $?
    [[ "$__et_tok" == "HS2:test:payload" ]]
  }
  run -0 f -S my_token
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — empty token variable yields empty local" {
  local my_token=""
  f() {
    eval "$(hs_extract_token f __et_tok "$@")" || return $?
    [[ -z "$__et_tok" ]]
  }
  run -0 f -S my_token
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — returns HS_ERR_STATE_VAR_UNINITIALIZED when -S absent" {
  f() { eval "$(hs_extract_token f __et_tok "$@")"; }
  run --separate-stderr f
  [[ "$status" -eq "$HS_ERR_STATE_VAR_UNINITIALIZED" ]]
  [[ "$stderr" == *"state variable is uninitialized"* ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — returns HS_ERR_MULTIPLE_STATE_INPUTS when -S given twice" {
  f() { local tok=""; eval "$(hs_extract_token f __et_tok "$@")"; }
  run --separate-stderr f -S tok -S tok
  [[ "$status" -eq "$HS_ERR_MULTIPLE_STATE_INPUTS" ]]
  [[ "$stderr" == *"option -S may only be given once"* ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — returns HS_ERR_INVALID_VAR_NAME for invalid -S identifier" {
  f() { eval "$(hs_extract_token f __et_tok "$@")"; }
  run f -S '1invalid'
  [[ "$status" -eq "$HS_ERR_INVALID_VAR_NAME" ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — returns HS_ERR_RESERVED_VAR_NAME for each reserved name" {
  f() { eval "$(hs_extract_token hs_extract_token __et_tok "$@")"; }
  local name
  while IFS= read -r name; do
    run --separate-stderr f -S "$name"
    [[ "$status" -eq "$HS_ERR_RESERVED_VAR_NAME" ]] || {
      printf 'expected HS_ERR_RESERVED_VAR_NAME for -S %s but got %d\n' "$name" "$status" >&2
      return 1
    }
    [[ "$stderr" == *"is reserved"* ]]
  done < <(hs_extract_token --list-reserved)
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token --list-reserved exits 0 with non-empty output" {
  run -0 hs_extract_token --list-reserved
  [[ -n "$output" ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token --list-reserved output identical to hs_persist_state --list-reserved" {
  local out_et out_ps
  run -0 hs_extract_token --list-reserved
  [[ -n "$output" ]]
  out_et="$output"
  run -0 hs_persist_state --list-reserved
  out_ps="$output"
  [[ "$out_et" == "$out_ps" ]]
}

# bats test_tags=hs_extract_token,issue-143
@test "hs_extract_token eval-code --list-reserved form declares no list_reserved local and mints a mode token" {
  ro_entry_point() {
    eval "$(hs_extract_token ro_entry_point __ro_tok "$@")" || return $?
    # No list_reserved sentinel local is declared anywhere (old design removed).
    [[ -z "${list_reserved@A}" ]] || { echo "list_reserved was declared" >&2; return 1; }
    # The token local carries a mode token, not an empty string.
    [[ "$__ro_tok" == HS2:mode=list-reserved:* ]] || { echo "not a mode token: $__ro_tok" >&2; return 1; }
    [[ "$__ro_tok" == *"reserved_names"* ]]        || { echo "no reserved_names payload: $__ro_tok" >&2; return 1; }
    echo OK
  }
  run -0 --separate-stderr ro_entry_point --list-reserved
  [[ "$output" == "OK" ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token eval-code --list-reserved form rejects extra arguments" {
  f() { eval "$(hs_extract_token f __et_tok "$@")"; }
  run -"$HS_ERR_INVALID_ARGUMENT_TYPE" --separate-stderr f --list-reserved extra
  [[ "$stderr" == *"--list-reserved takes no other arguments"* ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token collision scenario — eval form reads outer caller value not shadowing local" {
  # This test verifies the eval pattern prevents the collision bug.
  # A local named __hs_remaining exists before the eval; if the subshell
  # incorrectly resolved -S __hs_remaining to the local's unset copy, the
  # extracted value would be empty instead of the real token.
  outer_collision_test() {
    local __hs_remaining="should-not-be-seen"
    local outer_tok="real-token-value"
    eval "$(hs_extract_token outer_collision_test __et_tok "$@")" || return $?
    [[ "$__et_tok" == "real-token-value" ]]
  }
  run -0 outer_collision_test -S outer_tok
}

# bats test_tags=hs_extract_token,issue-136
@test "hs_extract_token — local name equals -S variable name: extracted value is preserved" {
  # Validates that hs_extract_token __tok -S __tok works correctly when the
  # destination local and the state variable share the same name.  The subshell
  # reads the outer __tok value before eval declares the new local, so the
  # extracted value must equal the original state variable value.
  f() {
    local __tok="token-value"
    eval "$(hs_extract_token f __tok "$@")" || return $?
    [[ "$__tok" == "token-value" ]]
  }
  run -0 f -S __tok
}

# ---------------------------------------------------------------------------
# hs_finalize_token
# ---------------------------------------------------------------------------

# bats test_tags=hs_finalize_token,issue-143
@test "hs_finalize_token without -S is a read-only no-op returning success" {
  # -S-optional relaxation: a normal token with no -S writes nothing and
  # succeeds (read-only w.r.t. external state), rather than erroring as the
  # former hs_write_token did with HS_ERR_STATE_VAR_UNINITIALIZED.
  f() {
    local __wt_tok=""
    eval "$(hs_finalize_token f __wt_tok)" || return $?
  }
  run -0 --separate-stderr f
  [[ -z "$output" ]]
}

# bats test_tags=hs_finalize_token,issue-143
@test "hs_finalize_token — returns HS_ERR_RESERVED_VAR_NAME when -S names a reserved variable" {
  f() { eval "$(hs_finalize_token hs_persist_state __wt_tok "$@")"; }
  local name
  while IFS= read -r name; do
    run --separate-stderr f -S "$name"
    [[ "$status" -eq "$HS_ERR_RESERVED_VAR_NAME" ]] || {
      printf 'expected HS_ERR_RESERVED_VAR_NAME for -S %s but got %d\n' "$name" "$status" >&2
      return 1
    }
    [[ "$stderr" == *"is reserved"* ]]
  done < <(hs_persist_state --list-reserved)
}

# bats test_tags=hs_extract_token,hs_finalize_token,issue-143
@test "entry point --list-reserved equals hs_persist_state --list-reserved plus token local" {
  # hs_persist_state --list-reserved is the canonical enumeration of the
  # shared parsing machinery's collision surface.  A read-write entry point
  # built on the token utilities must report exactly that set plus its own
  # token local: any missing canonical name is an under-report that lets a
  # caller pick a -S name the machinery shadows (silent state corruption); any
  # extra name is an unjustified new reservation.  Exact set equality is
  # asserted in both directions (PR #140 thread on the former superset test).
  rw_entry() {
    eval "$(hs_extract_token rw_entry __rw_tok "$@")" || return $?
    eval "$(hs_finalize_token rw_entry __rw_tok "$@")" || return $?
  }
  local name
  local -A expected=() reported=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && expected["$name"]=1
  done < <(hs_persist_state --list-reserved)
  expected["__rw_tok"]=1
  run -0 --separate-stderr rw_entry --list-reserved
  while IFS= read -r name; do
    [[ -n "$name" ]] && reported["$name"]=1
  done <<< "$output"
  for name in "${!expected[@]}"; do
    [[ -n "${reported[$name]+x}" ]] || {
      printf 'reserved name %s missing from rw_entry --list-reserved output\n' "$name" >&2
      return 1
    }
  done
  for name in "${!reported[@]}"; do
    [[ -n "${expected[$name]+x}" ]] || {
      printf 'extra name %s reported beyond hs_persist_state surface plus token local\n' "$name" >&2
      return 1
    }
  done
}

# bats test_tags=hs_finalize_token,issue-143
@test "hs_finalize_token --list-reserved direct query exits 0 with non-empty output" {
  run -0 hs_finalize_token --list-reserved
  [[ -n "$output" ]]
}

# bats test_tags=hs_finalize_token,issue-143
@test "hs_finalize_token --list-reserved direct query rejects extra arguments" {
  f() { hs_finalize_token --list-reserved extra; }
  run --separate-stderr f
  [[ "$status" -eq "$HS_ERR_INVALID_ARGUMENT_TYPE" ]]
  [[ "$stderr" == *"--list-reserved takes no other arguments"* ]]
}

# bats test_tags=hs_extract_token,issue-136
@test "--list-reserved collision-surface size — hs_extract_token reports less than 2 names" {
  local count=0 name
  while IFS= read -r name; do
    (( ++count ))
    # In-loop regression guard: fail fast on runaway --list-reserved output
    # instead of spinning until the test timeout (see the hs_persist_state
    # collision-surface size test).
    [[ "$count" -le 2 ]] || {
      printf 'more than 2 reserved names reported: runaway or grown --list-reserved output\n' >&2
      return 1
    }
  done < <(hs_extract_token --list-reserved)
  [[ "$count" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# issue #143 — token-borne --list-reserved mode (preliminary tests)
# These illustrate the documented new behaviour and are expected to FAIL until
# the implementation lands (hs_finalize_token, hs_is_list_reserved_mode,
# hs_read_only, the HS2 mode-token marker, and HS_ERR_LIST_RESERVED_TOKEN).
# ---------------------------------------------------------------------------

# bats test_tags=issue-143
@test "HS_ERR_LIST_RESERVED_TOKEN is defined as 13" {
  [[ -n "${HS_ERR_LIST_RESERVED_TOKEN:-}" ]] && [[ "$HS_ERR_LIST_RESERVED_TOKEN" -eq 13 ]]
}

# bats test_tags=hs_extract_token,issue-143
@test "hs_extract_token --list-reserved mints a mode token carrying reserved_names" {
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    [[ "$__tok" == HS2:mode=list-reserved:* ]] || { echo "marker: $__tok" >&2; return 1; }
    [[ "$__tok" == *reserved_names* ]]         || { echo "payload: $__tok" >&2; return 1; }
  }
  run -0 --separate-stderr f --list-reserved
}

# bats test_tags=hs_is_list_reserved_mode,issue-143
@test "hs_is_list_reserved_mode distinguishes a mode token from a real token" {
  producer() { local x=1; hs_persist_state "$@" -- x; }
  local state=""
  producer -S state
  # One entry point exercises both cases: --list-reserved yields a mode token,
  # -S <real state> yields an ordinary token.
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    hs_is_list_reserved_mode -S __tok && echo MODE || echo NORMAL
  }
  run -0 --separate-stderr f --list-reserved
  [[ "$output" == MODE ]]
  run -0 --separate-stderr f -S state
  [[ "$output" == NORMAL ]]
}

# bats test_tags=hs_finalize_token,issue-143
@test "hs_finalize_token writes the updated token back through dynamic scope" {
  local dest="old"                       # declared in the caller frame, before f
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    __tok="new-value"
    eval "$(hs_finalize_token f __tok "$@")" || return $?
  }
  f -S dest                              # called directly (no run subshell) so the write is observable
  [[ "$dest" == "new-value" ]]           # finalize wrote into the caller-frame variable via dynamic scope
}

# bats test_tags=hs_read_only,issue-143
@test "entry point --list-reserved excludes the token local when read-only" {
  ro() {
    eval "$(hs_extract_token ro __rotok "$@")" || return $?
    eval "$(hs_read_only     ro __rotok "$@")"
    hs_is_list_reserved_mode -S __rotok || { _ro "$@" || return $?; }
    eval "$(hs_finalize_token ro __rotok "$@")" || return $?
  }
  _ro() { :; }
  run -0 --separate-stderr ro --list-reserved
  [[ "$output" == *"__hs_processed"* ]]
  [[ "$output" != *"__rotok"* ]]
}

# bats test_tags=hs_extract_token,issue-143
@test "list-reserved report captures a stray local declared before extract" {
  f() {
    local leaked_before=1
    eval "$(hs_extract_token f __tok "$@")" || return $?
    hs_is_list_reserved_mode -S __tok || { :; }
    eval "$(hs_finalize_token f __tok "$@")" || return $?
  }
  run -0 --separate-stderr f --list-reserved
  [[ "$output" == *"leaked_before"* ]]
}

# bats test_tags=hs_finalize_token,issue-143
@test "list-reserved report captures a stray local declared between the evals" {
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    local leaked_between=1
    hs_is_list_reserved_mode -S __tok || { :; }
    eval "$(hs_finalize_token f __tok "$@")" || return $?
  }
  run -0 --separate-stderr f --list-reserved
  [[ "$output" == *"leaked_between"* ]]
}

# bats test_tags=hs_persist_state,hs_read_persisted_state,issue-143
@test "a mode token handed to a normal consumer is rejected with a stderr diagnostic" {
  # Handing a mode token to a normal consumer is a structural (programmer) error,
  # so the library must both return HS_ERR_LIST_RESERVED_TOKEN and print a
  # diagnostic explaining the problem on stderr.
  # hs_persist_state has no -q: the diagnostic is always printed.
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?   # __tok becomes a mode token
    local x=1
    hs_persist_state -S __tok -- x
  }
  run --separate-stderr f --list-reserved
  [[ "$status" -eq "${HS_ERR_LIST_RESERVED_TOKEN:-13}" ]]
  [[ "$stderr" == *"list-reserved"* ]]

  # hs_read_persisted_state has -q; -q suppresses missing-variable warnings, not
  # this structural error, so the diagnostic is still printed under -q.
  g() {
    eval "$(hs_extract_token g __tok "$@")" || return $?
    local y
    hs_read_persisted_state -q -S __tok -- y
  }
  run --separate-stderr g --list-reserved
  [[ "$status" -eq "${HS_ERR_LIST_RESERVED_TOKEN:-13}" ]]
  [[ "$stderr" == *"list-reserved"* ]]
}

# bats test_tags=hs_read_only,issue-143
@test "hs_read_only strips -S from the argument list in normal mode" {
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    eval "$(hs_read_only     f __tok "$@")"
    printf '%s' "$*"
  }
  run -0 --separate-stderr f -S dest
  [[ "$output" != *"-S"* ]]
}

# ---------------------------------------------------------------------------
# issue #143 — edge cases
# ---------------------------------------------------------------------------

# bats test_tags=hs_read_only,issue-143
@test "hs_read_only strips the bundled -Svar option form" {
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    eval "$(hs_read_only     f __tok "$@")"
    printf '%s' "$*"
  }
  run -0 --separate-stderr f -Sdest
  [[ "$output" != *"-S"* ]]
}

# bats test_tags=hs_read_only,issue-143
@test "hs_read_only is idempotent on an already read-only mode token" {
  ro() {
    eval "$(hs_extract_token ro __rotok "$@")" || return $?
    eval "$(hs_read_only     ro __rotok "$@")"   # appends -ro
    eval "$(hs_read_only     ro __rotok "$@")"   # no-op (already -ro)
    [[ "$__rotok" == HS2:mode=list-reserved-ro:* ]] || { echo "marker: $__rotok" >&2; return 1; }
    [[ "$__rotok" != *-ro-ro* ]]                    || { echo "double: $__rotok" >&2; return 1; }
    echo OK
  }
  run -0 --separate-stderr ro --list-reserved
  [[ "$output" == "OK" ]]
}

# bats test_tags=hs_read_only,hs_finalize_token,issue-143
@test "read-only entry point reads state but leaves it unchanged" {
  producer() { local counter=5; hs_persist_state "$@" -- counter; }
  local state=""
  producer -S state
  local before="$state"
  ro_entry() {
    eval "$(hs_extract_token ro_entry __ro_tok "$@")" || return $?
    eval "$(hs_read_only     ro_entry __ro_tok "$@")"
    hs_is_list_reserved_mode -S __ro_tok || { _ro_body "$@" || return $?; }
    eval "$(hs_finalize_token ro_entry __ro_tok "$@")" || return $?
  }
  _ro_body() {
    local counter
    eval "$(hs_read_persisted_state -S __ro_tok)" || return $?
    [[ "$counter" == "5" ]]      # read works
  }
  ro_entry -S state              # direct call so dynamic-scope writes would be visible
  [[ "$state" == "$before" ]]    # ... but read-only leaves external state untouched
}

# bats test_tags=hs_destroy_state,issue-143
@test "a mode token handed to hs_destroy_state is rejected discriminably" {
  f() {
    eval "$(hs_extract_token f __tok "$@")" || return $?
    hs_destroy_state -S __tok -- x
  }
  run --separate-stderr f --list-reserved
  [[ "$status" -eq "$HS_ERR_LIST_RESERVED_TOKEN" ]]
  [[ "$stderr" == *"list-reserved"* ]]
}

return 0

# --- Change History -------------------------------------------------------
# | PR    | Summary                                                        |
# |-------|----------------------------------------------------------------|
# | #38   | do not return state via stdout                                 |
# | #60   | use ${BASH:-bash} for collision-check subprocess [closes #59]  |
# | #63   | refactor safer handle-state restoration flow [closes #62]      |
# | #83   | fix hs_destroy_state rebuild subprocess helper [closes #82]    |
# | #86   | shellcheck fixes [closes #85]                                  |
# | #99   | error on undeclared variable names [closes #1]                 |
# | #102  | guard nameref restore against undeclared variables [cls #100]  |
# | #103  | reject function names with HS_ERR_UNKNOWN_VAR_NAME             |
# | #105  | fix hs_persist_state dropping indexed array elements [cls #3]  |
# | #108  | fix shellcheck linter errors in bats file [closes #107]        |
# | #109  | reduce nameref collision surface [closes #104]                 |
# | #110  | document HS_ERR_MULTIPLE_STATE_INPUTS for all entry points     |
# | #140  | add hs_extract_token and hs_write_token; entry-point pattern        |
# | #140  | fix --list-reserved merge for read-write entry points [closes #136] |
