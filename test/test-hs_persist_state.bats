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

# bats test_tags=hs_is_array
@test "_hs_is_array matches indexed and associative array attributes" {
  # shellcheck disable=SC2016
  # shellcheck disable=SC2329
  f() {
    local -a indexed=(one two)
    local -A assoc=([key]=value)
    _hs_is_array indexed &&
    _hs_is_array -A assoc &&
    ! _hs_is_array assoc &&
    ! _hs_is_array -A indexed
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_is_array
@test "_hs_is_array recognizes declared but uninitialized arrays" {
  # shellcheck disable=SC2329
  f() {
    local -a indexed
    local -A assoc
    _hs_is_array indexed &&
    _hs_is_array -A assoc &&
    ! _hs_is_array -A indexed &&
    ! _hs_is_array assoc
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_is_array
@test "_hs_is_array rejects integers and strings" {
  # shellcheck disable=SC2329
  f() {
    local -i number=42
    local text="hello"
    ! _hs_is_array number &&
    ! _hs_is_array -A number &&
    ! _hs_is_array text &&
    ! _hs_is_array -A text
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_is_array
@test "_hs_is_array works through namerefs for array targets" {
  # shellcheck disable=SC2329
  # shellcheck disable=SC2034
  f() {
    local -a indexed=(one two)
    local -A assoc=([key]=value)
    local -n indexed_ref=indexed
    local -n assoc_ref=assoc
    _hs_is_array indexed_ref &&
    _hs_is_array -A assoc_ref &&
    ! _hs_is_array assoc_ref &&
    ! _hs_is_array -A indexed_ref
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_is_array
@test "_hs_is_array rejects scalar namerefs" {
  # shellcheck disable=SC2329
  # shellcheck disable=SC2034
  f() {
    local text="hello"
    local -i number=42
    local -n text_ref=text
    local -n number_ref=number
    ! _hs_is_array text_ref &&
    ! _hs_is_array -A text_ref &&
    ! _hs_is_array number_ref &&
    ! _hs_is_array -A number_ref
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a non-array remaining_args container" {
  # shellcheck disable=SC2329
  f() {
    local remaining_args=""
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state foo
  }
  run -"$HS_ERR_INVALID_ARGUMENT_TYPE" --separate-stderr f
  [[ "$stderr" == *"'remaining_args' must name an indexed array variable"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a non-associative processed_args container" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -a processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state foo
  }
  run -"$HS_ERR_INVALID_ARGUMENT_TYPE" --separate-stderr f
  [[ "$stderr" == *"'processed_args' must name an associative array variable"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs parses known options and preserves remaining arguments" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=([old]=x)
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args bad -q -S state -- foo bar
    printf "%s|%s|%s" "${processed_args[state]}" "${processed_args[quiet]}" "${remaining_args[*]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|bad" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts trailing variable names into processed vars" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args bad -q -S state -- foo bar
    printf "%s|%s|%s|%s" "${processed_args[state]}" "${processed_args[quiet]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|bad|foo bar " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves explicit variable order in processed vars" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state -- alpha beta gamma
    printf "%s" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "alpha beta gamma " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves trailing variable order without explicit separator" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -q -S state alpha beta gamma
    printf "%s|%s|%s" "${processed_args[state]}" "${processed_args[quiet]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|true|alpha beta gamma" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs treats only the last separator as explicit variable-list start" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state -- alpha -- beta
    printf "%s|%s" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "-- alpha|beta " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts explicit vars after a trailing separator even with prior words" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state 1 -- alpha beta
    printf "%s|%s" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "1|alpha beta " ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves trailing vars after unknown option and parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state -b alpha beta
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b|alpha beta" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs allows forwarded unknown option parameters before trailing vars" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S state -c 1 -b beta gamma
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-c 1 -b|beta gamma" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a missing -S option" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -q foo
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects an invalid -S variable name" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args -S 1invalid foo
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid'"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects -S without a parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args qS: processed_args bad -S
  }
  run -"$HS_ERR_MISSING_ARGUMENT" --separate-stderr f
  [[ "$stderr" == *"missing required parameter to option -S"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves an unknown short option without parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args S: processed_args -a -S state foo
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-a|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves an unknown short option and its parameter" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args S: processed_args -b toto -S state foo
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b toto|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs extracts vars after unknown forwarded options" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args S: processed_args -b toto -S state foo bar
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|-b toto|foo bar" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs preserves forwarded bare words outside the vars list" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper remaining_args S: processed_args -S state 1invalid foo
    printf "%s|%s|%s" "${processed_args[state]}" "${remaining_args[*]}" "${processed_args[vars]}"
  }
  run -0 --separate-stderr f
  [ "$output" = "state|1invalid|foo" ]
  [[ "$stderr" == *"use -- before the variable names"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a remaining_args name reserved by the helper" {
  # shellcheck disable=SC2329
  f() {
    local -a __trailing_vars=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper __trailing_vars qS: processed_args -S state alpha beta gamma
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'__trailing_vars' is a reserved internal name"* ]]
}

# ---------------------------------------------------------------------------
# hs_read_persisted_state

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state errors on undeclared restore target" {
  # shellcheck disable=SC2329
  f() {
    init() { local bar=v2; hs_persist_state -S "$1" -- bar || return $?; }
    local state=""
    init state || return $?
    # bar is not declared as local in f — must error, not silently create a global
    hs_read_persisted_state -S state -- bar
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
    init()    { local foo=secret bar=v2 baz=new; hs_persist_state -S "$1" -- foo bar baz || return $?; }
    cleanup() { local foo bar baz; hs_read_persisted_state -S "$1" -- foo bar baz || return $?; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 f
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state -q does not suppress guard errors" {
  # shellcheck disable=SC2329
  f() {
    init() { local bar=v2; hs_persist_state -S "$1" -- bar || return $?; }
    local state=""
    init state || return $?
    # -q suppresses missing-variable warnings but must not suppress guard errors
    hs_read_persisted_state -q -S state -- bar
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"is not declared in scope"* ]]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state all-or-nothing: does not restore any var when a later var fails" {
  # shellcheck disable=SC2329
  f() {
    init() { local foo=a bar=b; hs_persist_state -S "$1" -- foo bar || return $?; }
    local state=""
    init state || return $?
    local foo
    # bar is not declared — validation must fail before any restoration occurs
    local err=0
    hs_read_persisted_state -S state -- foo bar || err=$?
    # foo must remain unset: all-or-nothing means no partial restoration
    printf "%s" "${foo:-UNSET}"
    return "$err"
  }
  run -"$HS_ERR_UNKNOWN_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'bar' is not declared in scope"* ]]
  [ "$output" = "UNSET" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state explicit form targets unset var in ancestor scope" {
  # shellcheck disable=SC2329
  init()   { local outer_var=from_init; hs_persist_state -S "$1" -- outer_var || return $?; }
  inner()  { hs_read_persisted_state -S "$1" -- outer_var || return $?; }
  middle() { local outer_var; inner "$1" || return $?; printf "%s" "$outer_var"; }
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
    init()    { local foo=secret bar=v2 baz=new; hs_persist_state -S "$1" -- foo bar baz || return $?; }
    cleanup() { local state="$1"; local foo bar baz; eval "$(hs_read_persisted_state -S state)" || return $?; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }
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
    init(){ local foo=secret bar=v2 baz=new; hs_persist_state -S "$1" -- foo bar baz || return $?; }
    cleanup(){
      local state_var="$1"
      local foo bar baz
      hs_read_persisted_state -S "$state_var" -- foo baz || return $?
      printf "%s:%s:%s" "$foo" "${bar:-}" "$baz"
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
      local foo bar
      hs_read_persisted_state -S "$state_var" -- foo bar || return $?
      printf "%s:%s" "$foo" "${bar:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'bar' is not defined in the state."* ]]
  [ "$output" = "secret:" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state warns for each missing requested variable" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state -S "$1" -- foo || return $?; }
    cleanup(){
      local state_var="$1"
      local foo bar baz
      hs_read_persisted_state -S "$state_var" -- foo bar baz || return $?
      printf "%s:%s:%s" "$foo" "${bar:-}" "${baz:-}"
    }
    local state=""
    init state || return $?
    cleanup state
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'bar' is not defined in the state."* ]]
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable 'baz' is not defined in the state."* ]]
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
  [[ "$stderr" == *"missing required state variable name"* ]]
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
  inner()  { hs_read_persisted_state -S "$1" -- items || return $?; }
  middle() {
    local -a items
    inner "$1" || return $?
    printf "%s:%s:%s" "${items[0]-}" "${items[1]-}" "${items[2]-}"
  }
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

# ---------------------------------------------------------------------------
# hs_persist_state

# bats test_tags=hs_persist_state
@test "hs_persist_state produces an HS2-format state string" {
  # shellcheck disable=SC2329
  f() {
    local state=""
    local scalar="value"
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
    local target="value"
    local -n ref=target
    local state=""
    hs_persist_state -S state -- ref || return $?
  }
  run -"$HS_ERR_NAMEREF_TARGET_NOT_PERSISTED" --separate-stderr f
  [ -z "$output" ]
  [[ "$stderr" == *"ref"* ]]
  [[ "$stderr" == *"target"* ]]
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
@test "hs_persist_state rejects all current explicit reserved persisted variable names" {
  # shellcheck disable=SC2329
  f() {
    local reserved
    local state
    init() {
      local __hsp_vars=bad
      local __hsp_existing=bad
      local __hsp_out_var=bad
      local __hsp_remaining=bad
      hs_persist_state -S "$1" -- "$2" || return $?
    }
    for reserved in __hsp_vars __hsp_existing __hsp_out_var __hsp_remaining; do
      state=""
      init state "$reserved" || return $?
    done
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state with -S var_name assigns state to variable" {
  # shellcheck disable=SC2329
  f() {
    local encoded=""
    init()    { local bar=two; hs_persist_state -S "$1" -- bar || return $?; }
    cleanup() { local bar; hs_read_persisted_state -S "$1" -- bar || return $?; printf "%s" "$bar"; }
    init encoded || return $?
    cleanup encoded
  }
  run -0 f
  [ "$output" = "two" ]
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
