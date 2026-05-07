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
  # Core functions (always present)
  export -f guard
  declare -f _cg_resolve_command_path >/dev/null 2>&1 && export -f _cg_resolve_command_path || true
  # New functions added in issue #112 (present after Task 5; silently skip if absent)
  export -f cg_safe_resolver cg_path_resolver cg_safe_run cg_unsafe cg_command_not_found_handler 2>/dev/null || true
  export CG_ERR_INVALID_NAME CG_ERR_NOT_FOUND
  export CG_ERR_MISSING_ARGUMENT CG_ERR_PATH_VIOLATION CG_ERR_SYNTAX_ERROR _CG_DEFAULT_PATH
}

# bats test_tags=guard,issue-24
# Expected to fail until CG_ERR_MISSING_COMMAND is removed from command_guard.sh
@test "issue-24: CG_ERR_MISSING_COMMAND is not defined after sourcing" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    source "$LIB"
    [[ -z "${CG_ERR_MISSING_COMMAND+x}" ]]
  '
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
# --- Multiple commands support ---

# bats test_tags=guard,pr1
@test "guard accepts multiple commands" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname date hostname
  '
}

# bats test_tags=guard,pr1
@test "multiple commands all create wrapper functions" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname date hostname
    [ "$(type -t uname)" = "function" ]
    [ "$(type -t date)" = "function" ]
    [ "$(type -t hostname)" = "function" ]
  '
}

# bats test_tags=guard,pr1
@test "multiple guarded commands execute correctly" {
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
@test "failure in one command stops processing, acts as no-op" {
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
@test "backward compatible with single command" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard uname
    [ "$(type -t uname)" = "function" ]
    out="$(uname)"
    [ -n "$out" ]
  '
}

# --- name=path token syntax ---

# bats test_tags=guard,pr2
@test "guard accepts cmd=path syntax" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname"
  '
}

# bats test_tags=guard,pr2
@test "custom path command creates wrapper function" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname"
    [ "$(type -t uname)" = "function" ]
  '
}

# bats test_tags=guard,pr2
@test "custom path command executes with specified path" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "kernel=/usr/bin/uname"
    out="$(kernel -s)"
    [ -n "$out" ]
  '
}

# bats test_tags=guard,pr2
@test "mix of custom path and regular commands" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard "uname=/usr/bin/uname" date hostname
    [ "$(type -t uname)" = "function" ]
    [ "$(type -t date)" = "function" ]
    [ "$(type -t hostname)" = "function" ]
  '
}

# bats test_tags=guard,pr2
@test "custom path with nonexistent file fails" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_NOT_FOUND" bash --noprofile -lc '
    guard "badcmd=/nonexistent/path/badcmd"
  '
  [[ "$output" == *"unable to resolve"* ]]
}

# bats test_tags=guard,pr2
@test "custom path with non-executable fails" {
  local tmpfile
  tmpfile=$(mktemp)
  run -"$CG_ERR_NOT_FOUND" bash --noprofile -lc "guard 'notexec=${tmpfile}'"
  rm -f "$tmpfile"
}

# bats test_tags=guard,pr2
@test "custom path with relative path fails" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_SYNTAX_ERROR" bash --noprofile -lc '
    guard "cmd=../bin/cmd"
  '
  [[ "$output" == *"absolute path"* ]]
}

# bats test_tags=guard,pr2
@test "invalid syntax in cmd=path fails gracefully" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_INVALID_NAME" bash --noprofile -lc '
    guard "bad-name=/usr/bin/test"
  '
  [[ "$output" == *"invalid command identifier"* ]]
}

# --- PATH enforcement: cg_safe_run, cg_unsafe, command_not_found_handle ---

# bats test_tags=guard,cg_safe_run
@test "cg_safe_run executes a guarded function" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard uname
    _func() { uname -s; }
    cg_safe_run _func
  '
  [[ -n "$output" ]]
}

# bats test_tags=guard,cg_safe_run
@test "non-guarded external command fails inside cg_safe_run" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile --norc -lc '
    source "$LIB"
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  '
  [[ "$output" == *"exit:127"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "cg_unsafe restores writable PATH inside cg_safe_run" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    _init() { cg_unsafe guard uname; }
    _func() { _init; uname -s; }
    cg_safe_run _func
  '
  [[ -n "$output" ]]
}

# bats test_tags=guard,cg_safe_run
@test "cg_safe_run rejects non-function argument" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_INVALID_NAME" --separate-stderr bash --noprofile -lc '
    source "$LIB"
    cg_safe_run not_a_function
  '
  [[ "$stderr" == *"[ERROR] cg_safe_run:"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG=1 prints WARNING for non-guarded command" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile --norc -c '
    source "$LIB"
    export CG_DEBUG=1
    nonexistent_cmd_cg_test_xyz
    echo "exit:$?"
  '
  [[ "$stderr" == *"[WARNING] guard: non-guarded command"* ]]
  [[ "$output" == *"exit:127"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG=1 suggests guard path inside cg_safe_run" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile --norc -lc '
    source "$LIB"
    export CG_DEBUG=1
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  '
  [[ "$stderr" == *"[WARNING] Suggestion: guard uname="* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG unset is silent for non-guarded command" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile --norc -lc '
    source "$LIB"
    unset CG_DEBUG
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  '
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "command_not_found_handle not installed when already defined" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    command_not_found_handle() { echo "CUSTOM_HANDLER"; return 127; }
    source "$LIB"
    nonexistent_cmd_cg_test_xyz
    echo "exit:$?"
  '
  [[ "$output" == *"CUSTOM_HANDLER"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "cg_command_not_found_handler is chainable" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile --norc -c '
    source "$LIB"
    export CG_DEBUG=1
    command_not_found_handle() {
      echo "APP_HANDLER:$1"
      cg_command_not_found_handler "$@"
    }
    nonexistent_cmd_cg_test_xyz
    echo "exit:$?"
  '
  [[ "$output" == *"APP_HANDLER:nonexistent_cmd_cg_test_xyz"* ]]
  [[ "$stderr" == *"[WARNING] guard: non-guarded command"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "guard -r resolver uses provided function for path resolution" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    my_resolver() {
      local cmd="${@: -1}"
      [[ "$cmd" == "uname" ]] || return 3
      printf "/usr/bin/uname"
    }
    guard -r my_resolver uname
    [ "$(type -t uname)" = "function" ]
    out=$(uname)
    [ -n "$out" ]
  '
}

# --- Zero commands and options support ---

# bats test_tags=guard,pr4
@test "guard with zero commands emits warning and returns 0" {

  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    guard
  '
  [[ "$stderr" == *"[WARNING] guard: no commands specified."* ]]
}

# bats test_tags=guard,pr4
@test "guard with -q suppresses warnings for zero commands" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    guard -q
  '
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "guard with -- separates options from commands" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard -- uname
    [ "$(type -t uname)" = "function" ]
  '
}

# bats test_tags=guard,pr4
@test "guard with -q -- suppresses warnings and separates options" {
  # shellcheck disable=SC2016
  run -0 --separate-stderr bash --noprofile -lc '
    guard -q --
    [ "$(type -t uname)" != "function" ]
  '
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "guard backward compatible with single command after options" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    guard -q -- uname
    [ "$(type -t uname)" = "function" ]
  '
}

# --- prefix (-p) option ---

# bats test_tags=guard,prefix
@test "guard -p prefix_ creates prefixed wrapper for plain-name tokens" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard -p mylib_ uname date
    [ "$(type -t mylib_uname)" = "function" ]
    [ "$(type -t mylib_date)" = "function" ]
    [ "$(type -t uname)" != "function" ]
  '
}

# bats test_tags=guard,prefix
@test "guard -p does not apply prefix to fname=path tokens" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard -p mylib_ "myuname=/usr/bin/uname"
    [ "$(type -t myuname)" = "function" ]
    [ "$(type -t mylib_myuname)" != "function" ]
  '
}

# --- Extended token forms ---

# bats test_tags=guard,tokens
@test "guard fname=name resolves name via active resolver" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    guard "kernel=uname"
    [ "$(type -t kernel)" = "function" ]
    out=$(kernel -s)
    [ -n "$out" ]
  '
}

# bats test_tags=guard,tokens
@test "guard /abs/path creates wrapper with prefixed basename" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile -lc '
    source "$LIB"
    uname_path="$(PATH=/usr/bin:/bin command -v uname)"
    guard -p mylib_ "$uname_path"
    [ "$(type -t mylib_uname)" = "function" ]
    out=$(mylib_uname)
    [ -n "$out" ]
  '
}

# bats test_tags=guard,tokens
@test "guard fname=name with relative rhs is rejected" {
  # shellcheck disable=SC2016
  run -"$CG_ERR_SYNTAX_ERROR" bash --noprofile -lc '
    source "$LIB"
    guard "mybash=../bin/bash"
  '
}

# --- Environmental regression tests ---
# These tests verify undocumented Bash behaviors the library relies on.
# No skip — must always pass. A failure indicates a Bash regression that
# would break the library on this platform.

# bats test_tags=guard,envtest
@test "envtest: local VAR in callee shadows local -r VAR from parent without error" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    outer() {
      local -r MYVAR="readonly_value"
      inner
    }
    inner() {
      local MYVAR="writable_value"
      [ "$MYVAR" = "writable_value" ]
    }
    outer
  '
}

# bats test_tags=guard,envtest
@test "envtest: local VAR fails when variable is globally readonly" {
  # shellcheck disable=SC2016
  run bash --noprofile --norc -c '
    readonly GLOBALVAR="fixed"
    inner() {
      local GLOBALVAR="new_value"
    }
    inner
  '
  [[ "$status" -ne 0 ]]
}

# bats test_tags=guard,envtest
@test "envtest: local -r PATH prevents command resolution within function scope" {
  # Directly relevant to cg_safe_run: local -r PATH to a fake value makes
  # 'command -v' fail, and the outer scope is unaffected after the call.
  local saved_path="$PATH"
  _cg_env3_restricted() {
    local -r PATH="/nonexistent-cg-env3-test"
    command -v uname 2>/dev/null
    printf 'lookup_exit:%d' $?
  }
  local result
  result="$(_cg_env3_restricted)"
  [[ "$result" == "lookup_exit:1" ]]
  [[ "$PATH" == "$saved_path" ]]
}

# bats test_tags=guard,envtest
@test "envtest: command_not_found_handle sees parent dynamic-scope local PATH" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    checker() {
      local PATH="/sentinel-path"
      nonexistent_cmd_cg_envtest_xyz
    }
    command_not_found_handle() {
      [[ "$PATH" == "/sentinel-path" ]] && echo "SEEN_LOCAL_PATH"
      return 127
    }
    checker
    echo "done"
  '
  [[ "$output" == *"SEEN_LOCAL_PATH"* ]]
}

# bats test_tags=guard,envtest
@test "envtest: command -pv resolves commands independently of local PATH" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    fake_path_func() {
      local PATH="/nonexistent-fake"
      result="$(command -pv uname)"
      [[ "$result" == /*/uname ]] && echo "RESOLVED_CORRECTLY"
    }
    fake_path_func
  '
  [[ "$output" == *"RESOLVED_CORRECTLY"* ]]
}

# bats test_tags=guard,envtest
@test "envtest: eval-defined functions inside functions are globally scoped" {
  # shellcheck disable=SC2016
  run -0 bash --noprofile --norc -c '
    definer() {
      eval "my_evaled_fn() { echo evaled; }"
    }
    definer
    [ "$(type -t my_evaled_fn)" = "function" ]
    my_evaled_fn
  '
  [[ "$output" == *"evaled"* ]]
}
