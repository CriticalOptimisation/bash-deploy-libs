#!/usr/bin/env bats

# Bats tests for hs_persist_state_as_code
# Run with: bats test/test-hs_persist_state_as_code.bats

setup_file() {
  bats_require_minimum_version 1.5.0
  # directory of this test file; handle_state.sh is at ../config
  export LIB="$BATS_TEST_DIRNAME/../config/handle_state.sh"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
  export BATS_TEST_TMPDIR
  # shellcheck source=../config/handle_state.sh
  #source "$LIB"
  #export -f _hs_is_valid_variable_name \
  #          _hs_resolve_state_inputs _hs_extract_persisted_state_var_names \
  #          hs_persist_state_as_code hs_destroy_state hs_read_persisted_state
  #export HS_ERR_RESERVED_VAR_NAME HS_ERR_VAR_NAME_COLLISION HS_ERR_VAR_NAME_NOT_IN_STATE
  #export HS_ERR_MULTIPLE_STATE_INPUTS HS_ERR_CORRUPT_STATE HS_ERR_INVALID_VAR_NAME \
  #       HS_ERR_STATE_VAR_UNINITIALIZED HS_ERR_MISSING_ARGUMENT HS_ERR_INVALID_ARGUMENT_TYPE
  # Accelerate test failure
  export BATS_TEST_TIMEOUT=30
}
setup() {
  # shellcheck source=../config/handle_state.sh
  source "$LIB"
}
# Define a helper to create a fake simplified persisted state
make_state() {
  while [ "$#" -gt 0 ]; do
    local var_name="$1"
    shift
    local var_value="${1-}"
    shift
    printf 'local %s=%q\n' "$var_name" "$var_value"
  done
}
# Define a helper to create corrupted persisted state
corrupt_state() {
  if [ "$#" -ne 1 ]; then
    echo "Usage: corrupt_state <slow|error>" >&2
    return 1
  fi
  local mode="$1"
  case "$mode" in
    slow)
      # Create a state that sleeps for 10 seconds when evaluated
      printf 'sleep %i\n' "$((BATS_TEST_TIMEOUT + 1))"
      ;;
    error)
      # Create a state that produces an error when evaluated
      printf 'invalid_command_that_fails\n'
      ;;
    *)
      echo "Unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}
export -f make_state corrupt_state # makes it available in bash --noprofile -lc calls

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
  [ "$output" = "state|-b|toto foo" ]
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
  [ "$output" = "state|-b|toto foo bar" ]
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
@test "_hs_resolve_state_inputs rejects a remaining_args name that collides with a local helper variable" {
  # shellcheck disable=SC2329
  f() {
    local -a __trailing_vars=()
    local -A processed_args=()
    _hs_resolve_state_inputs my_helper __trailing_vars qS: processed_args -S state alpha beta gamma
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'__trailing_vars' conflicts with a local variable name"* ]]
}

# bats test_tags=hs_resolve_state_inputs
@test "_hs_resolve_state_inputs rejects a processed_args name that collides with a local helper variable" {
  # shellcheck disable=SC2329
  f() {
    local -a remaining_args=()
    local __options=""
    _hs_resolve_state_inputs my_helper remaining_args qS: __options -S state alpha beta gamma
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"'__options' conflicts with a local variable name"* ]]
}

# bats test_tags=hs_persist_state_as_code
@test "eval without local should succeed and leave globals unchanged" {
  # shellcheck disable=SC2329
  f() {
    init() { local bar=v2; local baz=new; hs_persist_state_as_code -S "$1" bar baz; }
    state=""
    init state
    baz=old
    eval "$state"
    printf "%s:%s" "$bar" "$baz"
  }
  run -0 f
  # Succeeds but does not set variables
  [[ "$output" == ":old" ]]
  g() {
    init(){ local bar=v2; local baz=new; hs_persist_state_as_code -S "$1" bar baz; }
    state=""
    init state
    baz=old
    eval "$state" 2>/dev/null || true
    [ -z "${bar+set}" ] && [ "${baz}" = "old" ]
  }
  run -0 g
}

# bats test_tags=hs_persist_state_as_code
@test "cleanup declares local and eval restores values onto new locals" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state_as_code -S "$1" foo bar baz; }
    cleanup(){ local -n state_ref="$1"; local foo bar baz; eval "$state_ref"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }
    state=""
    init state
    cleanup state
  }
  run -0 f
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state
@test "eval the output of (hs_read_persisted_state ...) in caller scope restores values" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state_as_code -S "$1" foo bar baz; }
    cleanup(){ local state="$1"; local foo bar baz; eval "$(hs_read_persisted_state -S state)"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }
    set -x
    state=""
    init state
    cleanup "$state"
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state accepts explicit -S state" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    state=""
    init state
    printf "%s" "$(hs_read_persisted_state -S state)"
  }
  run -0 --separate-stderr f
  [[ "$output" == *'hs_read_persisted_state -q -S state'* ]]
  [[ "$output" == *'local -p | while IFS= read -r __hs_local_decl; do'* ]]
  [[ "$output" == *') >/dev/null'* ]]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state
@test "hs_read_persisted_state restores only requested variables" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state_as_code -S "$1" foo bar baz; }
    cleanup(){
      local state_var="$1"
      local foo="" bar="" baz=""
      hs_read_persisted_state -S "$state_var" foo baz
      printf "%s:%s:%s" "$foo" "${bar:-}" "$baz"
    }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    outer(){
      local foo=""
      inner_auto
      printf "%s:" "$foo"
      foo=""
      inner_explicit
      printf "%s" "$foo"
    }
    inner_auto(){
      eval "$(hs_read_persisted_state -S state)"
    }
    inner_explicit(){
      hs_read_persisted_state -S state foo
    }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){
      local state_var="$1"
      local foo="" bar=""
      hs_read_persisted_state -S "$state_var" foo bar
      printf "%s:%s" "$foo" "${bar:-}"
    }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){
      local state_var="$1"
      local foo="" bar="" baz=""
      hs_read_persisted_state -S "$state_var" foo bar baz
      printf "%s:%s:%s" "$foo" "${bar:-}" "${baz:-}"
    }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){
      local state_var="$1"
      local foo="" bar=""
      hs_read_persisted_state -q -S "$state_var" foo bar
      printf "%s:%s" "$foo" "${bar:-}"
    }
    state=""
    init state
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
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){
      local state_var="$1"
      local foo="" bar=""
      hs_read_persisted_state -S "$state_var" -q foo bar
      printf "%s:%s" "$foo" "${bar:-}"
    }
    state=""
    init state
    cleanup state
  }
  run -0 --separate-stderr f
  [ "$output" = "secret:" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_read_persisted_state,known_issue
@test "known issue nr.7: hs_read_persisted_state does not reject internal requested variable name __requested_var_ref explicitly" {
  # shellcheck disable=SC2329
  f() {
    local state='if local -p foo >/dev/null 2>&1; then foo=ok; fi'
    local __requested_var_ref=""
    hs_read_persisted_state -S state __requested_var_ref
    printf "%s" "$__requested_var_ref"
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [[ "$stderr" == *"[WARNING] hs_read_persisted_state: variable '__requested_var_ref' is not defined in the state."* ]]
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
    state=""
    hs_read_persisted_state -S state >/dev/null
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"state variable 'state' is not set or is empty"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "overwriting a local already set in cleanup should fail with explicit message" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){ local foo=already; eval "$1"; }
    state=""
    init state
    cleanup "$state"
  }
  run -1 f
  [[ "$output" == *"local foo already defined; refusing to overwrite"* ]]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code reports the first colliding variable name" {
  # shellcheck disable=SC2329
  f() {
    init_existing() {
      local foo=one bar=two
      hs_persist_state_as_code -S "$1" foo bar
    }
    init_again() {
      local foo=three bar=four baz=five
      hs_persist_state_as_code -S "$1" foo bar baz
    }
    state=""
    init_existing state
    init_again state
  }
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr f
  [[ "$stderr" == *"variable already defined in the state: foo."* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code detects a collision when prior state initializes an empty array" {
  # shellcheck disable=SC2329
  f() {
    local state='if local -p foo >/dev/null 2>&1; then
  foo=([0]="")
fi'
    init_again() {
      local foo=three
      hs_persist_state_as_code -S "$1" foo
    }
    init_again state
  }
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr f
  [[ "$stderr" == *"variable already defined in the state: foo."* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code does not include variables that were not set in init" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=one; hs_persist_state_as_code -S "$1" foo bar; }
    cleanup(){ local foo bar; eval "$1"; printf "%s:%s" "$foo" "${bar:-}"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state_as_code,known_issue
@test "known issue nr.1: hs_persist_state_as_code silently ignores unknown variable names" {
  # shellcheck disable=SC2329
  f() {
    state=""
    init(){ hs_persist_state_as_code -S "$1" not_a_var; }
    init state
    printf "%s" "$state"
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code,known_issue
@test "known issue nr.2: hs_persist_state_as_code silently ignores function names" {
  # shellcheck disable=SC2329
  f() {
    state=""
    init(){ my_func(){ echo "nope"; }; hs_persist_state_as_code -S "$1" my_func; }
    init state
    printf "%s" "$state"
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code,known_issue
@test "known issue nr.3: hs_persist_state_as_code only captures the first element of an indexed array" {
  # shellcheck disable=SC2329
  f() {
    init(){ local -a items=(one two); hs_persist_state_as_code -S "$1" items; }
    cleanup(){ local -a items; eval "$1"; printf "%s:%s" "${items[0]-}" "${items[1]-}"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state_as_code,known_issue
@test "known issue nr.4: hs_persist_state_as_code silently ignores associative arrays" {
  # shellcheck disable=SC2329
  # shellcheck disable=SC2034
  f() {
    state=""
    init(){ local -A amap=([key]=value); hs_persist_state_as_code -S "$1" amap; }
    init state
    printf "%s" "$state"
  }
  run -0 --separate-stderr f
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code,known_issue
@test "known issue nr.5: hs_persist_state_as_code persists namerefs as scalar values" {
  # shellcheck disable=SC2329
  f() {
    init(){ local target=secret; local -n ref=target; hs_persist_state_as_code -S "$1" ref; }
    cleanup(){ local target=""; local -n ref=target; eval "$1"; printf "%s:%s" "$target" "$ref"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ "$output" = "secret:secret" ]
}

# bats test_tags=hs_persist_state_as_code
@test "restore empty value" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=""; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "overwrite empty local variable with persisted value" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo=secret; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){ local foo=""; eval "$1"; printf "%s" "$foo"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ "$output" = "secret" ]
}

# bats test_tags=hs_persist_state_as_code
@test "preserve special characters in persisted values" {
  # shellcheck disable=SC2329
  f() {
    init(){ local foo='a b "c" $d'; hs_persist_state_as_code -S "$1" foo; }
    cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; }
    state=""
    init state
    cleanup "$state"
  }
  run -0 f
  [ "$output" = "a b \"c\" \$d" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -S detects an invalid variable name" {
  # shellcheck disable=SC2329
  f() { hs_persist_state_as_code -S "1invalid-var-name"; }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code ignores forwarded args before final --" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=two
      hs_persist_state_as_code bad -S "$1" -- foo
    }
    cleanup() {
      local foo=""
      eval "$state"
      printf "%s" "$foo"
    }
    state=""
    init state
    cleanup
  }
  run -0 --separate-stderr f
  [ "$output" = "two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code rejects an invalid persisted variable name" {
  # shellcheck disable=SC2329
  f() {
    state=""
    init() {
      local foo=two
      hs_persist_state_as_code -S "$1" -- "1invalid-var-name" foo
    }
    init state
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code requires -S" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=two bar=three
      hs_persist_state_as_code foo bar
    }
    init
  }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __var_name" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local __var_name=bad
      hs_persist_state_as_code -S "$1" __var_name
    }
    state=""
    init state
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name '__var_name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __existing_state" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local __existing_state=bad
      hs_persist_state_as_code -S "$1" __existing_state
    }
    state=""
    init state
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name '__existing_state'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __output_state_var" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local __output_state_var=bad
      hs_persist_state_as_code -S "$1" __output_state_var
    }
    state=""
    init state
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name '__output_state_var'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __output" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local __output=bad
      hs_persist_state_as_code -S "$1" __output
    }
    state=""
    init state
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name '__output'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code rejects all current explicit reserved persisted variable names" {
  # shellcheck disable=SC2329
  f() {
    local reserved
    local state
    init() {
      local __var_name=bad
      local __existing_state=bad
      local __output_state_var=bad
      local __output=bad
      hs_persist_state_as_code -S "$1" "$2"
    }
    for reserved in __var_name __existing_state __output_state_var __output; do
      state=""
      init state "$reserved" || return $?
    done
  }
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"refusing to persist reserved variable name"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -S var_name assigns to variable" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local bar=two
      hs_persist_state_as_code -S "$1" bar
    }
    cleanup(){
      local bar
      eval "$state"
      printf "%s" "$bar"
    }
    init state
    cleanup
  }
  run -0 f
  [ "$output" = "two" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code detects corrupt state var: error on eval" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=two
      hs_persist_state_as_code "$@" foo
    }
    state_var="$(corrupt_state error)"
    init -S state_var
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" =~ "prior state is corrupted" ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state with -S rewrites the named variable in place" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=one bar=two
      hs_persist_state_as_code -S "$1" foo bar
    }
    cleanup() {
      local foo="" bar=""
      eval "$state"
      printf "%s:%s" "${foo:-}" "${bar:-}"
    }
    state=""
    init state
    hs_destroy_state -S state foo
    cleanup
  }
  run -0 --separate-stderr f
  [[ "$output" == *":two"* ]]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rebuild works in a clean shell without exported helper functions" {
  run -0 --separate-stderr env -i PATH="$PATH" LIB="$LIB" bash --noprofile -lc '
    source "$LIB"
    init() {
      local foo=one bar=two
      hs_persist_state_as_code -S "$1" -- foo bar
    }
    cleanup() {
      local foo="" bar=""
      eval "$1"
      printf "%s:%s" "${foo:-}" "${bar:-}"
    }
    state=""
    init state
    hs_destroy_state -S state -- foo
    cleanup "$state"
  '
  [ "$output" = ":two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state requires -S" {
  # shellcheck disable=SC2329
  f() { hs_destroy_state foo bar >/dev/null; }
  run -"$HS_ERR_STATE_VAR_UNINITIALIZED" --separate-stderr f
  [[ "$stderr" == *"missing required -S <statevar> option"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects invalid destroy variable names" {
  # shellcheck disable=SC2329
  f() {
    state="if local -p foo >/dev/null 2>&1; then
  foo=one
fi"
    hs_destroy_state -S state -- "1invalid-var-name" >/dev/null
  }
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr f
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state ignores forwarded args before final --" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=one bar=two
      hs_persist_state_as_code -S "$1" foo bar
    }
    cleanup() {
      local foo="" bar=""
      eval "$state"
      printf "%s:%s" "${foo:-}" "${bar:-}"
    }
    state=""
    init state
    hs_destroy_state bad -S state -- foo
    cleanup
  }
  run -0 --separate-stderr f
  [ "$output" = ":two" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state fails when asked to remove a variable not present in the state" {
  # shellcheck disable=SC2329
  f() {
    init() {
      local foo=one
      hs_persist_state_as_code -S "$1" foo
    }
    state=""
    init state
    hs_destroy_state -S state missing >/dev/null
  }
  run -"$HS_ERR_VAR_NAME_NOT_IN_STATE" --separate-stderr f
  [[ "$stderr" == *"variable 'missing' is not defined in the state"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state detects corrupt prior state" {
  # shellcheck disable=SC2329
  f() {
    local state
    state="$(corrupt_state error)"
    hs_destroy_state -S state foo >/dev/null
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"prior state is corrupted"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state,known_issue
@test "known issue nr.6: hs_destroy_state does not reject internal state variable name __state_var_names explicitly" {
  # shellcheck disable=SC2329
  f() {
    local __state_var_names='not a state snippet'
    hs_destroy_state -S __state_var_names foo >/dev/null
  }
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr f
  [[ "$stderr" == *"prior state is corrupted"* ]]
  [ -z "$output" ]
}
