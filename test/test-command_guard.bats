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
# --- PR#1: Multiple commands support (should fail initially) ---

# bats test_tags=guard,pr1
@test "PR#1: guard accepts multiple commands" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname date hostname
  '
}

# bats test_tags=guard,pr1
@test "PR#1: multiple commands all create wrapper functions" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname date hostname
    [ "$(type -t uname)" = "function" ]
    [ "$(type -t date)" = "function" ]
    [ "$(type -t hostname)" = "function" ]
  '
}

# bats test_tags=guard,pr1
@test "PR#1: multiple guarded commands execute correctly" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname echo
    out1="$(uname)"
    out2="$(echo test)"
    [ -n "$out1" ]
    [ "$out2" = "test" ]
  '
}

# bats test_tags=guard,pr1
@test "PR#1: failure in one command stops processing, acts as no-op" {
  # shellcheck disable=SC2016
  run bash --noprofile -lc '
    guard uname nonexistent_xyz date
    echo "EXIT_CODE:$?"
    type -t uname
  '
  [[ "${lines[0]}" == *"[ERROR] guard: unable to resolve full path"* ]]
  [[ "${lines[1]}" == "EXIT_CODE:3" ]]
  [[ "${lines[2]}" == "file" ]]
}

# bats test_tags=guard,pr1
@test "PR#1: backward compatible with single command" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname
    [ "$(type -t uname)" = "function" ]
    out="$(uname)"
    [ -n "$out" ]
  '
}

# --- PR#2: Custom path syntax (should fail initially) ---

# bats test_tags=guard,pr2
@test "PR#2: guard accepts cmd=path syntax" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname"
  '
}

# bats test_tags=guard,pr2
@test "PR#2: custom path command creates wrapper function" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname"
    [ "$(type -t uname)" = "function" ]
  '
}

# bats test_tags=guard,pr2
@test "PR#2: custom path command executes with specified path" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname"
    out="$(uname)"
    [ -n "$out" ]
  '
}

# bats test_tags=guard,pr2
@test "PR#2: mix of custom path and regular commands" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname" date hostname
    [ "$(type -t uname)" = "function" ]
    [ "$(type -t date)" = "function" ]
    [ "$(type -t hostname)" = "function" ]
  '
}

# bats test_tags=guard,pr2
@test "PR#2: custom path with nonexistent file fails" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" bash --noprofile -lc '
    guard "badcmd=/nonexistent/path/badcmd"
  '
  [[ "$output" == *"unable to resolve"* ]]
}

# bats test_tags=guard,pr2
@test "PR#2: custom path with non-executable fails" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" bash --noprofile -lc '
    tmpfile=$(mktemp)
    guard "notexec=$tmpfile"
    rm -f "$tmpfile"
  '
}

# bats test_tags=guard,pr2
@test "PR#2: custom path with relative path fails" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" bash --noprofile -lc '
    guard "cmd=../bin/cmd"
  '
  [[ "$output" == *"absolute path"* ]]
}

# bats test_tags=guard,pr2
@test "PR#2: invalid syntax in cmd=path fails gracefully" {
  skip "Feature not yet implemented - PR#2"
  # shellcheck disable=SC2016
  run -"$CG_ERR_INVALID_NAME" bash --noprofile -lc '
    guard "bad-name=/usr/bin/test"
  '
  [[ "$output" == *"invalid command identifier"* ]]
}

# --- PR#3: PATH enforcement and debug trap (should fail initially) ---

# bats test_tags=guard,pr3
@test "PR#3: original PATH is saved on source" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    original="$PATH"
    source "$LIB"
    [ -n "${_ORIGINAL_PATH}" ]
    [ "${_ORIGINAL_PATH}" = "$original" ]
  '
}

# bats test_tags=guard,pr3
@test "PR#3: PATH is unset after sourcing" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    [ -z "${PATH+x}" ] && echo "PATH_UNSET" || echo "PATH_SET"
  '
  [[ "$output" == *"PATH_UNSET"* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: non-guarded command fails when PATH unset" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -127 bash --noprofile -lc '
    source "$LIB"
    curl --version
  '
}

# bats test_tags=guard,pr3
@test "PR#3: guarded command works despite unset PATH" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard uname
    out="$(uname)"
    [ -n "$out" ]
  '
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap catches non-guarded command in debug mode" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -127 --separate-stderr bash --noprofile -lc '
    set -x
    source "$LIB"
    curl --version 2>&1 || true
  '
  [[ "$stderr" == *"WARNING: Non-guarded command attempted: curl"* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap suggests guard command with path" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run --separate-stderr bash --noprofile -lc '
    set -x
    source "$LIB"
    ls / 2>&1 || true
  '
  [[ "$stderr" == *"Suggestion: guard ls="* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap uses default PATH for suggestions" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run --separate-stderr bash --noprofile -lc '
    set -x
    source "$LIB"
    uname 2>&1 || true
  '
  [[ "$stderr" == *"Suggestion: guard uname=/usr/bin/uname"* ]] ||
  [[ "$stderr" == *"Suggestion: guard uname=/bin/uname"* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap falls back to original PATH" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run --separate-stderr bash --noprofile -lc '
    export PATH="/custom/bin:$PATH"
    set -x
    source "$LIB"
    # Try a command that might only be in custom location
    fakecmd 2>&1 || true
  '
  [[ "$stderr" == *"Suggestion:"* ]] || [[ "$stderr" == *"WARNING:"* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap does not trigger for guarded commands" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    set -x
    source "$LIB"
    guard uname
    uname > /dev/null 2>&1
  '
  [[ "$stderr" != *"WARNING: Non-guarded command"* ]]
}

# bats test_tags=guard,pr3
@test "PR#3: debug trap does not trigger for builtins" {
  skip "Feature not yet implemented - PR#3"
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    set -x
    source "$LIB"
    echo "test" > /dev/null 2>&1
  '
  [[ "$stderr" != *"WARNING: Non-guarded command"* ]]
}

# --- PR#4: Zero commands and options support (should fail initially) ---

# bats test_tags=guard,pr4
@test "PR#4: guard with zero commands emits warning and returns 0" {
  skip "Feature not yet implemented - PR#4"
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    source "$LIB"
    guard
  '
  [[ "$stderr" == *"WARNING: No commands specified"* ]]
}

# bats test_tags=guard,pr4
@test "PR#4: guard with -q suppresses warnings for zero commands" {
  skip "Feature not yet implemented - PR#4"
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    source "$LIB"
    guard -q
  '
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "PR#4: guard with -- separates options from commands" {
  skip "Feature not yet implemented - PR#4"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard -- uname
    [ "$(type -t uname)" = "function" ]
  '
}

# bats test_tags=guard,pr4
@test "PR#4: guard with -q -- suppresses warnings and separates options" {
  skip "Feature not yet implemented - PR#4"
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    source "$LIB"
    guard -q --
    [ "$(type -t uname)" != "function" ]
  '
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "PR#4: guard backward compatible with single command after options" {
  skip "Feature not yet implemented - PR#4"
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard -q -- uname
    [ "$(type -t uname)" = "function" ]
  '
}
