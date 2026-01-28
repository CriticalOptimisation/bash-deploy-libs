#!/usr/bin/env bats

# Bats tests for hs_persist_state
# Run with: bats test/test-hs_persist_state.bats

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
  source "$LIB"  # run hs_setup_output_to_stdout
  hs_cleanup_output  # ensure clean state at start
  export -f hs_setup_output_to_stdout hs_cleanup_output hs_get_pid_of_subshell\
            hs_persist_state hs_read_persisted_state hs_echo
  export HS_ERR_RESERVED_VAR_NAME HS_ERR_VAR_NAME_COLLISION
  # Accelerate test failure
  export BATS_TEST_TIMEOUT=2
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
export -f make_state  # makes it available in bash --noprofile -lc calls

# bats test_tags=hs_setup_output_to_stdout, hs_echo
@test "hs_setup_output_to_stdout sets up output redirection [no-setup]" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  hs_setup_output_to_stdout;  # in 'run' ensure bats captures output
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

# bats test_tags=hs_persist_state
@test "eval without local should succeed and leave globals unchanged" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init() { local bar=v2; local baz=new; hs_persist_state bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state"; 
  printf "%s:%s" "$bar" "$baz";'
  # Succeeds but does not set variables
  [[ "$output" == ":old" ]]
  # ensure globals were not created or overwritten
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local bar=v2; local baz=new; hs_persist_state bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state" 2>/dev/null || true; 
  [ -z "${bar+set}" ] && [ "${baz}" = "old" ]'
}

# bats test_tags=hs_persist_state,focus
@test "cleanup declares local and eval restores values onto new locals" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; };
  cleanup(){ local foo bar baz; eval "$1"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; 
  state=$(init); 
  cleanup "$state";
  '
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_read_persisted_state,focus
@test "eval \$(hs_read_persisted_state ...) in caller scope restores values" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc ' 
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; 
  cleanup(){ local foo bar baz; eval "$(hs_read_persisted_state "$1")"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "secret:v2:new" ]
}

# bats test_tags=hs_persist_state
@test "overwriting a local already set in cleanup should fail with explicit message" {
  # shellcheck disable=SC2016
  run -1 bash --noprofile -lc '
  init(){ local foo=secret; hs_persist_state foo; };
  cleanup(){ local foo=already; eval "$1"; }; 
  state=$(init); 
  cleanup "$state"'
  [[ "$output" == *"local foo already defined; refusing to overwrite"* ]]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state does not include variables that were not set in init" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=one; hs_persist_state foo bar; };
  cleanup(){ local foo bar; eval "$1"; printf "%s:%s" "$foo" "${bar:-}"; };  
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state ignores unknown variable names" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ hs_persist_state not_a_var; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state ignores function names" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ my_func(){ echo "nope"; }; hs_persist_state my_func; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state only captures the first element of an indexed array" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local -a items=(one two); hs_persist_state items; };
  cleanup(){ local -a items; eval "$1"; printf "%s:%s" "${items[0]-}" "${items[1]-}"; };
  state=$(init);
  cleanup "$state"
  '
  [ "$output" = "one:" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state ignores associative arrays" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
  init(){ local -A amap=([key]=value); hs_persist_state amap; };
  state=$(init);
  printf "%s" "$state"
  '
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state treats namerefs as scalar values" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local target=secret; local -n ref=target; hs_persist_state ref; };
  cleanup(){ local target=""; local -n ref=target; eval "$1"; printf "%s:%s" "$target" "$ref"; };
  state=$(init);
  cleanup "$state"
  '
  [ "$output" = "secret:secret" ]
}

# bats test_tags=hs_persist_state
@test "restore empty value" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=""; hs_persist_state foo; };
  cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; };  
  state=$(init); 
  cleanup "$state"'
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "overwrite empty local variable with persisted value" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo=secret; hs_persist_state foo; }; 
  cleanup(){ local foo=""; eval "$1"; printf "%s" "$foo"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "secret" ]
}

# bats test_tags=hs_persist_state
@test "preserve special characters in persisted values" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
  init(){ local foo='\''a b "c" $d'\''; hs_persist_state foo; }; 
  cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$output" = "a b \"c\" \$d" ]
}

# bats test_tags=hs_setup_output_to_stdout, hs_persist_state
@test "hs_setup_output_to_stdout keeps logs separate from persisted state [no-setup]" {
  # hs_echo logs to stdout, captured by bats, even though it is explicitly captured by $state.
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    hs_setup_output_to_stdout
    init() {
      local foo="secret"
      hs_echo "LOG foo is $foo"
      hs_persist_state foo
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

# bats test_tags=hs_persist_state
@test "hs_persist_state with -s appends to existing state" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    init() {
      local bar=two
      hs_persist_state -s "$1" bar
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

# bats test_tags=hs_persist_state
@test "hs_persist_state with -s fails on variable name collision" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_VAR_NAME_COLLISION" --separate-stderr bash --noprofile -lc '
    init() {
      local foo=two
      hs_persist_state -s "$1" foo  # Fails: foo already in state
    }
    state1=$(make_state foo one)
    init "$state1" >/dev/null  # Invalid output must be ignored
  '
  [[ "$stderr" == *"variable 'foo' is already defined in the state, with value 'one'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state fails on reserved variable name __var_name" {
  # shellcheck disable=SC2016
  run -"$HS_ERR_RESERVED_VAR_NAME" --separate-stderr bash --noprofile -lc '
    source "$LIB"
    init() {
      local __var_name=bad
      hs_persist_state __var_name
    }
    init
  '
  [[ "$stderr" == *"refusing to persist reserved variable name '__var_name'"* ]]
  [ -z "$output" ]
}

# bats test_tags=hs_persist_state
@test "hs_persist_state with -S var_name assigns to variable" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    init() {
      local bar=two
      hs_persist_state -S state bar
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
