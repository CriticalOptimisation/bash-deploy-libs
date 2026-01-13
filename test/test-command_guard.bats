#!/usr/bin/env bats

# Bats tests for command_guard
# Run with: bats test/test-command_guard.bats

setup_file() {
  bats_require_minimum_version 1.5.0
  export LIB="$BATS_TEST_DIRNAME/../config/command_guard.sh"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
  # shellcheck source=../config/command_guard.sh
  source "$LIB"
}

@test "guard defines a function that shadows the command" {
  run -0 bash --noprofile -lc '
    source "$BATS_TEST_DIRNAME/../config/command_guard.sh"
    guard uname
    [ "$(type -t uname)" = "function" ]
  '
}

@test "guarded command dispatches to the resolved full path" {
  run -0 bash --noprofile -lc '
    source "$BATS_TEST_DIRNAME/../config/command_guard.sh"
    guard uname
    full_path="$(PATH=/usr/bin:/bin command -v -- uname)"
    [ -x "$full_path" ]
    out_guarded="$(uname)"
    out_direct="$($full_path)"
    [ "$out_guarded" = "$out_direct" ]
  '
}

@test "guard rejects invalid function names" {
  run -2 bash --noprofile -lc '
    source "$BATS_TEST_DIRNAME/../config/command_guard.sh"
    guard "bad-name"
  '
  [[ "$output" == *"invalid command name"* ]]
}
