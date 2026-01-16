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
  # shellcheck source=config/command_guard.sh
  source "$LIB"
  export -f guard _cg_resolve_command_path
  export CG_ERR_MISSING_COMMAND CG_ERR_INVALID_NAME CG_ERR_NOT_FOUND
}

# bats test_tags=guard
@test "guard defines a function that shadows the command" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname
    [ "$(type -t uname)" = "function" ]
  '
}

# bats test_tags=guard
@test "guarded command dispatches to the resolved full path" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname
    full_path="$(PATH=/usr/bin:/bin command -v -- uname)"
    [ -x "$full_path" ]
    out_guarded="$(uname)"
    out_direct="$($full_path)"
    [ "$out_guarded" = "$out_direct" ]
  '
}

# bats test_tags=guard,focus
@test "guard rejects invalid function names" {
  run -"$CG_ERR_INVALID_NAME" bash --noprofile -lc '
    guard "bad-name"
  '
  [[ "$output" == *"invalid command identifier"* ]]
}

# bats test_tags=guard
@test "guard is not fooled by alias expansion" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" --separate-stderr bash --noprofile --norc -lc '
    shopt -s expand_aliases
    alias myalias="echo fooled"
    guard myalias
  '
  [[ "$stderr" == "[BUG] guard: 'myalias' is an alias"* ]]
}

# bats test_tags=guard
@test "guard is not fooled by a builtin" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" --separate-stderr bash --noprofile -lc '
    guard exec
  '
  [[ "$stderr" == "[BUG] guard: 'exec' is a builtin"* ]]
}

# bats test_tags=guard
@test "guard returns non-zero without exiting an interactive shell" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" --separate-stderr bash --noprofile --norc -lc '
    shopt -s expand_aliases
    alias myalias="echo fooled"
    guard myalias
    status=$?
    echo "after"
    exit "$status"
  '
  [[ "$output" == *"after"* ]]
  [[ "$stderr" == "[BUG] guard: 'myalias' is an alias"* ]]
}

# bats test_tags=guard
@test "guard exits when called from a subshell" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" --separate-stderr bash --noprofile --norc -lc '
    shopt -s expand_aliases
    alias myalias="echo fooled"
    (guard myalias; echo "inside")
    subshell_status=$?
    echo "subshell=$subshell_status"
    exit "$subshell_status"
  '
  [[ "$output" == *"subshell=3"* ]]
  [[ "$output" != *"inside"* ]]
  [[ "$stderr" == "[BUG] guard: 'myalias' is an alias"* ]]
}
