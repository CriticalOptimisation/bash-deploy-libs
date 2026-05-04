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
  export BATS_TEST_TIMEOUT=30
}
setup() {
  # shellcheck source=../config/handle_state.sh
  source "$LIB"
}

# Helper: return a non-HS2 string for corrupt-state tests.
hs2_corrupt_state() {
  printf 'NOTHS2:invalid'
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects caller that declared __hs_remaining as a non-array" {
  # shellcheck disable=SC2329
  f() {
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
@test "hs_persist_state rejects a state variable named __hs_processed" {
  # __hs_processed is declared local -A in hs_persist_state's entry-point frame.
  # Using it as the state variable name causes the updated state to be discarded
  # into the local associative array instead of the caller's variable.
  # The library must detect this early via _hs_resolve_state_inputs and return
  # HS_ERR_RESERVED_VAR_NAME rather than silently losing the persisted state.
  # shellcheck disable=SC2329
  f() {
    local __hs_processed=""
    init()    { local bar=two; hs_persist_state -S "$1" -- bar || return $?; }
    cleanup() { local bar; hs_read_persisted_state -S "$1" -- bar || return $?; printf "%s" "$bar"; }
    init __hs_processed || return $?
    cleanup __hs_processed
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
  local name
  while IFS= read -r name; do
    [[ "$name" == __hs_* ]] || { printf 'unexpected name: %s\n' "$name" >&2; return 1; }
  done < <(hs_persist_state --list-reserved)
}

# bats test_tags=hs_persist_state,hs_read_persisted_state,hs_destroy_state
@test "--list-reserved produces identical output from all three API entry points" {
  local out_persist out_read out_destroy
  out_persist=$(hs_persist_state --list-reserved)
  out_read=$(hs_read_persisted_state --list-reserved)
  out_destroy=$(hs_destroy_state --list-reserved)
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
  done < <(hs_persist_state --list-reserved)
  [[ "$count" -ge 1 ]]  # guards against vacuous pass when --list-reserved is broken
  [[ "$count" -le 2 ]]  # regression guard: target is exactly 2 (__hs_remaining, __hs_processed)
}
