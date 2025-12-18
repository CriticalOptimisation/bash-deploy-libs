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

@test "eval without local should fail and not create globals" {
  run bash -lc 'source "$LIB"; init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; state=$(init); baz=old; eval "$state" 2>&1'
  # Should fail because cleanup/local is not declared; check status and error message
  [ "$status" -ne 0 ]
  [[ "$output" == *"cleanup must declare local foo"* ]]
  # ensure globals were not created or overwritten
  run bash -lc 'source "$LIB"; init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; state=$(init); baz=old; eval "$state" 2>/dev/null || true; [ -z "${foo+set}" ] && [ -z "${bar+set}" ] && [ "${baz}" = "old" ]'
  [ "$status" -eq 0 ]
}

@test "cleanup declares local and eval restores values" {
  run bash -lc 'source "$LIB"; init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; state=$(init); cleanup(){ local foo bar baz; eval "$1"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "secret:v2:new" ]
}

@test "eval $(hs_read_persisted_state ...) in caller scope restores values" {
  run bash -lc 'source "$LIB"; init(){ local foo=secret; local bar=v2; local baz=new; hs_persist_state foo bar baz; }; state=$(init); cleanup(){ local foo bar baz; eval "$(hs_read_persisted_state "$1")"; printf "%s:%s:%s" "$foo" "$bar" "$baz"; }; cleanup "$state"'
  [ "$status" -eq 0 ]
  [ "$output" = "secret:v2:new" ]
}

@test "cleanup local already set should fail with explicit message" {
  run bash -lc 'source "$LIB"; init(){ local foo=secret; hs_persist_state foo; }; state=$(init); cleanup(){ local foo=already; eval "$1" 2>&1; }; cleanup "$state"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"local foo already set in cleanup"* ]]
}
