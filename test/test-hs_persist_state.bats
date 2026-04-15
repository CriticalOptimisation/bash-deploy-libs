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
  # shellcheck source=config/handle_state.sh
  # shellcheck disable=SC1091
  source "$LIB"  # run hs_setup_output_to_stdout
  hs_cleanup_output  # ensure clean state at start
  export -f hs_setup_output_to_stdout hs_cleanup_output hs_get_pid_of_subshell\
            _hs_resolve_state_inputs hs_persist_state_as_code hs_destroy_state hs_read_persisted_state hs_echo
  export HS_ERR_RESERVED_VAR_NAME HS_ERR_VAR_NAME_COLLISION HS_ERR_VAR_NAME_NOT_IN_STATE
  export HS_ERR_MULTIPLE_STATE_INPUTS HS_ERR_CORRUPT_STATE HS_ERR_INVALID_VAR_NAME
  # Accelerate test failure
  export BATS_TEST_TIMEOUT=30
}
# setup and teardown are skipped if the test has '[no-setup]' in its name.
# This allows the capture of hs_echo output by bats.
setup() {
  if [[ "$BATS_TEST_NAME" != *"-5bno-2dsetup-5d"* ]]; then
    # Most test depend on this setup, and output via hs_echo is not captured.
    hs_setup_output_to_stdout
  fi
}
teardown() {
  if [[ "$BATS_TEST_NAME" != *"-5bno-2dsetup-5d"* ]]; then
    hs_cleanup_output
  fi
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

# bats test_tags=hs_setup_output_to_stdout, hs_echo
@test "hs_setup_output_to_stdout sets up output redirection [no-setup]" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  hs_setup_output_to_stdout;  # in "run" ensure bats captures output
  init(){ hs_echo "bypasses stdout capture"; };
  state=$(init);
  hs_cleanup_output;
  '
  printf 'output=%s\n' "$output" >&2
  [[ "$output" == *"bypasses stdout capture"* ]]
}

# bats test_tags=hs_setup_output_to_stdout
@test "hs_setup_output_to_stdout is idempotent [no-setup]" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    hs_setup_output_to_stdout
    first_pid=$(hs_get_pid_of_subshell)
    hs_setup_output_to_stdout #>>"$out_file"
    second_pid=$(hs_get_pid_of_subshell)
    if [ "$first_pid" != "$second_pid" ]; then
      printf "pid changed %s -> %s" "$first_pid" "$second_pid"
      exit 1
    fi
    hs_cleanup_output
  '
  [[ "$stderr" == *"hs_setup_output_to_stdout: already set up; skipping."* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_setup_output_to_stdout
@test "hs_setup_output_to_stdout idempotent warning does not leak to stdout" {
  export out_file="$BATS_TEST_TMPDIR/stdout"
  : >"$out_file"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    hs_setup_output_to_stdout >>"$out_file"
  '
  # $output contains only stderr
  [[ "$output" == *"hs_setup_output_to_stdout: already set up; skipping."* ]]
  # out_file should be empty
  run cat "$out_file"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$out_file"
}

# bats test_tags=hs_persist_state_as_code
@test "eval without local should succeed and leave globals unchanged" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init() { local bar=v2; local baz=new; hs_persist_state_as_code bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state"; 
  printf "%s:%s" "$bar" "$baz";'
  # Succeeds but does not set variables
  [[ "$output" == ":old" ]]
  # ensure globals were not created or overwritten
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local bar=v2; local baz=new; hs_persist_state_as_code bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state" 2>/dev/null || true; 
  [ -z "${bar+set}" ] && [ "${baz}" = "old" ]'
}

# bats test_tags=hs_persist_state_as_code
@test "cleanup declares local and eval restores values onto new locals" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state_as_code foo bar baz; };
  cleanup(){ local foo bar baz; eval "$1"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; 
  state=$(init); 
  cleanup "$state";
  '
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state
@test "eval the output of (hs_read_persisted_state ...) in caller scope restores values" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc ' 
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state_as_code foo bar baz; }; 
  cleanup(){ local state="$1"; local foo bar baz; eval "$(hs_read_persisted_state state)"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; 
  set -x
  state=$(init) 
  cleanup "$state"'
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_persist_state_as_code
@test "overwriting a local already set in cleanup should fail with explicit message" {
  # shellcheck disable=SC2016
  run -1 bash --noprofile -lc '
  init(){ local foo=secret; hs_persist_state_as_code foo; };
  cleanup(){ local foo=already; eval "$1"; }; 
  state=$(init); 
  cleanup "$state"'
  [[ "$output" == *"local foo already defined; refusing to overwrite"* ]]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code does not include variables that were not set in init" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=one; hs_persist_state_as_code foo bar; };
  cleanup(){ local foo bar; eval "$1"; printf "%s:%s" "$foo" "${bar:-}"; };  
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code ignores unknown variable names" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ hs_persist_state_as_code not_a_var; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code ignores function names" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ my_func(){ echo "nope"; }; hs_persist_state_as_code my_func; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code only captures the first element of an indexed array" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local -a items=(one two); hs_persist_state_as_code items; };
  cleanup(){ local -a items; eval "$1"; printf "%s:%s" "${items[0]-}" "${items[1]-}"; };
  state=$(init);
  cleanup "$state"
  '
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code ignores associative arrays" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ local -A amap=([key]=value); hs_persist_state_as_code amap; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code treats namerefs as scalar values" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local target=secret; local -n ref=target; hs_persist_state_as_code ref; };
  cleanup(){ local target=""; local -n ref=target; eval "$1"; printf "%s:%s" "$target" "$ref"; };
  state=$(init);
  cleanup "$state"
  '
  [ "$output" = "secret:secret" ]
}

# bats test_tags=hs_persist_state_as_code
@test "restore empty value" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=""; hs_persist_state_as_code foo; };
  cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; };  
  state=$(init); 
  cleanup "$state"'
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "overwrite empty local variable with persisted value" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=secret; hs_persist_state_as_code foo; }; 
  cleanup(){ local foo=""; eval "$1"; printf "%s" "$foo"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "secret" ]
}

# bats test_tags=hs_persist_state_as_code
@test "preserve special characters in persisted values" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo='\''a b "c" $d'\''; hs_persist_state_as_code foo; }; 
  cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "a b \"c\" \$d" ]
}

# bats test_tags=hs_setup_output_to_stdout, hs_persist_state_as_code
@test "hs_setup_output_to_stdout keeps logs separate from persisted state [no-setup]" {
  # hs_echo logs to stdout, captured by bats, even though it is explicitly captured by $state.
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    hs_setup_output_to_stdout
    init() {
      local foo="secret"
      hs_echo "LOG foo is $foo"
      hs_persist_state_as_code foo
    }
    state=$(init)
    printf "%s\n" "$state" >&2  # send persisted state to stderr
    hs_cleanup_output
  '
  [ "$output" = "LOG foo is secret" ]
  [[ "$stderr" == *'foo=secret'* ]]
}

# This test uses kill -0 to check if a PID exists
# bats test_tags=hs_get_pid_of_subshell
@test "hs_get_pid_of_subshell returns a valid PID" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    pid=$(hs_get_pid_of_subshell)
    if ! kill -0 "$pid" 2>/dev/null; then
      printf "No such PID %s" "$pid"
      exit 1
    fi
    hs_cleanup_output
    printf "%s" "$pid"
  '
  [[ "$output" =~ ^[0-9]+$ ]]
} 

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -s appends to existing state" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    init() {
      local bar=two
      hs_persist_state_as_code -s "$1" bar
    }
    cleanup(){ 
      local foo bar 
      eval "$1"
      printf "%s:%s" "$foo" "$bar" 
    }
    state1=$(make_state foo one)
    state2=$(init "$state1")
    cleanup "$state2"
  '
  [ "$output" = "one:two" ]
  [ -z "$stderr" ]
} 

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -s fails on variable name collision" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr bash --noprofile -lc '
    init() {
      local foo=two
      hs_persist_state_as_code -s "$1" foo  # Fails: foo already in state
    }
    state1=$(make_state foo one)
    init "$state1" >/dev/null  # Invalid output must be ignored
  '
  # echo "stderr=$stderr" >&3
  [[ "$stderr" == *"variable 'foo' is already defined in the state, with value 'one'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -S detects an invalid variable name" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr bash --noprofile -xlc '
    hs_persist_state_as_code -S "1invalid-var-name"
  '
  [[ "$stderr" == *"invalid variable name '1invalid-var-name' for -S option"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __var_name" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr bash --noprofile -xlc '
    init() {
      local __var_name=bad
      hs_persist_state_as_code __var_name
    }
    init
  '
  [[ "$stderr" == *"refusing to persist reserved variable name '__var_name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __existing_state" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr bash --noprofile -lc '
    init() {
      local __existing_state=bad
      hs_persist_state_as_code __existing_state
    }
    init
  '
  [[ "$stderr" == *"refusing to persist reserved variable name '__existing_state'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __output_state_var" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr bash --noprofile -lc '
    init() {
      local __output_state_var=bad
      hs_persist_state_as_code __output_state_var
    }
    init
  '
  [[ "$stderr" == *"refusing to persist reserved variable name '__output_state_var'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code fails on reserved variable name __output" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr bash --noprofile -lc '
    init() {
      local __output=bad
      hs_persist_state_as_code __output
    }
    init
  '
  [[ "$stderr" == *"refusing to persist reserved variable name '__output'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code with -S var_name assigns to variable" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    init() {
      local bar=two
      hs_persist_state_as_code -S state bar
    }
    cleanup(){ 
      local bar 
      eval "$state"
      printf "%s" "$bar" 
    }
    init
    cleanup
  '
  [ "$output" = "two" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code detects corrupt state: infinite loop" {
  # The infinite loop is simulated by a 3 seconds sleep.
  # shellcheck disable=SC2016
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr bash --noprofile -lc '
    init() {
      local foo=two
      hs_persist_state_as_code -s "$(corrupt_state slow)" foo
    }
    init
  '
  [[ "$stderr" =~ "prior state is corrupted" ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code detects corrupt state: error on eval" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr bash --noprofile -lc '
    init() {
      local foo=two
      hs_persist_state_as_code -s "$(corrupt_state error)" foo
    }
    init
  '
  [[ "$stderr" =~ "prior state is corrupted" ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code detects corrupt state var: error on eval" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr bash --noprofile -lc '
    init() {
      local foo=two
      hs_persist_state_as_code "$@" foo
    }
    state_var="$(corrupt_state error)"
    init -S state_var
  '
  [[ "$stderr" =~ "prior state is corrupted" ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state_as_code
@test "hs_persist_state_as_code -s works when called via bats run on a shell function" {
  # Regression test for issue #59: hs_persist_state_as_code used $0 to re-invoke the
  # shell for collision checking, but $0 is the Bats runner (not bash) when a
  # function is invoked via 'bats run'.  The fix uses ${BASH:-bash} instead.
  # Also verifies that the collision-check subshell does not leak 'a' globally.
  state_accumulates() {
    local incoming_state="local a=kept"
    hs_persist_state_as_code -s "$incoming_state" b >/dev/null
  }
  run -0 --separate-stderr state_accumulates
  [ -z "$stderr" ]
  # a must not have leaked into the current scope from the collision-check subshell
  [ -z "${a+set}" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state with -s removes the listed variables and prints the rebuilt state" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    source "$LIB" 2>/dev/null
    hs_cleanup_output
    init() {
      local foo=one bar=two baz=three
      hs_persist_state_as_code foo bar baz
    }
    cleanup() {
      local foo="" bar="" baz=""
      eval "$1"
      printf "%s:%s:%s" "${foo:-}" "${bar:-}" "${baz:-}"
    }
    state=$(init)
    stripped=$(hs_destroy_state -s "$state" foo baz)
    cleanup "$stripped"
  '
  [[ "$output" == *":two:"* ]]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state with -S rewrites the named variable in place" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    source "$LIB" 2>/dev/null
    hs_cleanup_output
    init() {
      local foo=one bar=two
      hs_persist_state_as_code -S state foo bar
    }
    cleanup() {
      local foo="" bar=""
      eval "$state"
      printf "%s:%s" "${foo:-}" "${bar:-}"
    }
    init
    hs_destroy_state -S state foo
    cleanup
  '
  [[ "$output" == *":two"* ]]
  [ -z "$stderr" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state rejects invalid destroy variable names" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_INVALID_VAR_NAME" --separate-stderr bash --noprofile -lc '
    source "$LIB" 2>/dev/null
    hs_cleanup_output
    state=$(make_state foo one)
    hs_destroy_state -s "$state" "1invalid-var-name" >/dev/null
  '
  [[ "$stderr" == *"invalid variable name '1invalid-var-name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state fails when asked to remove a variable not present in the state" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_VAR_NAME_NOT_IN_STATE" --separate-stderr bash --noprofile -lc '
    source "$LIB" 2>/dev/null
    hs_cleanup_output
    init() {
      local foo=one
      hs_persist_state_as_code foo
    }
    state=$(init)
    hs_destroy_state -s "$state" missing >/dev/null
  '
  [[ "$stderr" == *"variable 'missing' is not defined in the state"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_destroy_state
@test "hs_destroy_state detects corrupt prior state" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_CORRUPT_STATE" --separate-stderr bash --noprofile -lc '
    source "$LIB" 2>/dev/null
    hs_cleanup_output
    hs_destroy_state -s "$(corrupt_state error)" foo >/dev/null
  '
  [[ "$stderr" == *"prior state is corrupted"* ]]
  [ -z "$output" ]
}
