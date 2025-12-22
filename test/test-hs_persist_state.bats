#!/usr/bin/env bats

# Bats tests for hs_persist_state
# Run with: bats test/test-hs_persist_state.bats

setup() {
  # directory of this test file; handle_state.sh is at ../config
  export LIB="$BATS_TEST_DIRNAME/../config/handle_state.sh"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
}

@test "eval without local should succeed and leave globals unchanged" {
  run bash -lc '
  source "$LIB"; 
  init() { local bar=v2; local baz=new; hs_persist_state bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state"; 
  hs_cleanup_output; 
  printf "%s:%s" "$bar" "$baz" 2>&1'
  # Succeeds but does not set variables
  [ "$status" -eq 0 ]
  [[ "$output" == ":old" ]]
  # ensure globals were not created or overwritten
  run bash -lc '
  source "$LIB"; 
  init(){ local bar=v2; local baz=new; hs_persist_state bar baz; }; 
  state=$(init); 
  baz=old; 
  eval "$state" 2>/dev/null || true; 
  hs_cleanup_output; 
  [ -z "${bar+set}" ] && [ "${baz}" = "old" ]'
  [ "$status" -eq 0 ]
}

@test "cleanup declares local and eval restores values onto new locals" {
  run bash -lc '
  source "$LIB"; 
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; };
  cleanup(){ local foo bar baz; eval "$1"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "secret:v2:new" ]
}

@test "eval \$(hs_read_persisted_state ...) in caller scope restores values" {
  run bash -lc ' 
  source "$LIB"; 
  init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; 
  cleanup(){ local foo bar baz; eval "$(hs_read_persisted_state "$1")"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "secret:v2:new" ]
}

@test "cleanup local already set should fail with explicit message" {
  run bash -lc '
  source "$LIB"; 
  init(){ local foo=secret; hs_persist_state foo; };
  cleanup(){ local foo=already; eval "$1" 2>&1; hs_cleanup_output; }; 
  state=$(init); 
  cleanup "$state"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"local foo already defined; refusing to overwrite"* ]]
}
@test "hs_persist_state does not include variables that were not set in init" {
  run bash -lc '
  source "$LIB"; 
  init(){ local foo=one; hs_persist_state foo bar; };
  cleanup(){ local foo bar; eval "$1"; printf "%s:%s" "$foo" "${bar:-}"; hs_cleanup_output; };  
  state=$(init); 
  cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "one:" ]
}

@test "restore empty value" {
  run bash -lc '
  source "$LIB"; 
  init(){ local foo=""; hs_persist_state foo; };
  cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; };  
  state=$(init); 
  cleanup "$state"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "overwrite empty local variable with persisted value" {
  run bash -lc 'source "$LIB"; init(){ local foo=secret; hs_persist_state foo; }; state=$(init); cleanup(){ local foo=""; eval "$1"; printf "%s" "$foo"; }; cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "secret" ]
}

@test "preserve special characters in persisted values" {
  run bash -lc 'source "$LIB"; init(){ local foo='\''a b "c" $d'\''; hs_persist_state foo; }; state=$(init); cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; }; cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "a b \"c\" \$d" ]
}

@test "hs_setup_output_to_stdio keeps logs off persisted state" {
  run bash -lc '
    source "$LIB"
    init() {
      local foo="secret"
      hs_echo "LOG foo is $foo"
      hs_persist_state foo
    }
    state=$(init)
    [[ "$state" != *"LOG foo"* ]]
    cleanup(){ local foo; eval "$1"; printf "%s" "$foo"; hs_cleanup_output; }
    cleanup "$state"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "LOG foo is secret" ]
  [ "${lines[1]}" = "secret" ]
}

@test "hs_get_pid_of_subshell returns a valid PID" {
  run bash -lc '
    source "$LIB"
    pid=$(hs_get_pid_of_subshell)
    if ! kill -0 "$pid" 2>/dev/null; then
      printf "No such PID %s" "$pid"
      exit 1
    fi
    exec 3>&-
    wait "$pid" 2>/dev/null || true
    printf "%s" "$pid"
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
} 

@test "hs_setup_output_to_stdout is idempotent" {
  run bash -lc '
    source "$LIB"
    first_pid=$(hs_get_pid_of_subshell)
    hs_setup_output_to_stdout
    second_pid=$(hs_get_pid_of_subshell)
    if [ "$first_pid" != "$second_pid" ]; then
      printf "pid changed %s -> %s" "$first_pid" "$second_pid"
      exit 1
    fi
    hs_cleanup_output
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[WARN] hs_setup_output_to_stdout: already set up; skipping." ]
}
