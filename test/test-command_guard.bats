#!/usr/bin/env bats

# Bats tests for command_guard
# Run with: bats test/test-command_guard.bats
# Disable "f is never called" for the entire file. It is called via "run".
# shellcheck disable=SC2329

setup_file() {
  bats_require_minimum_version 1.5.0
  export LIB="$BATS_TEST_DIRNAME/../config/command_guard.sh"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
}

setup() {
  # shellcheck source=../config/command_guard.sh
  source "$LIB"
  # Library functions and variables reach test subshells via BATS' process fork.
  # export LIB is the only export needed — for the one test that starts a fresh bash.
}

# bats test_tags=guard,issue-24
# Expected to fail until CG_ERR_MISSING_COMMAND is removed from command_guard.sh
@test "issue-24: CG_ERR_MISSING_COMMAND is not defined after sourcing" {
  [[ -z "${CG_ERR_MISSING_COMMAND+x}" ]]
}

# bats test_tags=guard
@test "cg_guard is defined after sourcing" {
  [[ "$(type -t cg_guard)" == "function" ]]
}

# bats test_tags=guard
@test "guard alias is defined after sourcing when unclaimed" {
  [[ "$(type -t guard)" == "function" ]]
}

# bats test_tags=guard
@test "guard alias is not installed when guard is already defined" {
  # Genuine fresh-shell test: guard must be defined before the library is sourced.
  # The sentinel prevents re-sourcing in the BATS process, so run bash is required.
  # shellcheck disable=SC2016  # $LIB is exported; it expands inside the subprocess, not here
  run -0 bash --noprofile --norc -c '
    guard() { echo "MY_GUARD"; }
    source "$LIB"
    guard
  '
  [[ "$output" == "MY_GUARD" ]]
}

# bats test_tags=guard
@test "guard defines a function that shadows the command" {
  f() {
    guard uname
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard
@test "guarded command dispatches to the resolved full path" {
  f() {
    guard uname
    local full_path
    full_path="$(PATH=/usr/bin:/bin command -v -- uname)"
    [[ -x "$full_path" ]]
    local out_guarded out_direct
    out_guarded="$(uname)"
    out_direct="$($full_path)"
    [[ "$out_guarded" == "$out_direct" ]]
  }
  run -0 f
}

# bats test_tags=guard
@test "guard rejects invalid function names" {
  f() { guard "bad-name"; }
  run -"$CG_ERR_INVALID_NAME" f
  [[ "$output" == *"invalid command identifier"* ]]
}

# bats test_tags=guard
@test "guard is not fooled by alias expansion" {
  f() {
    shopt -s expand_aliases
    alias myalias="echo fooled"
    guard myalias
  }
  run -"$CG_ERR_NOT_FOUND" --separate-stderr f
  [[ "$stderr" == "[BUG] cg_guard: 'myalias' is an alias"* ]]
}

# bats test_tags=guard
@test "guard is not fooled by a builtin" {
  f() { guard exec; }
  run -"$CG_ERR_NOT_FOUND" --separate-stderr f
  [[ "$stderr" == "[BUG] cg_guard: 'exec' is a builtin"* ]]
}

# bats test_tags=guard
@test "guard returns non-zero without exiting an interactive shell" {
  f() {
    shopt -s expand_aliases
    alias myalias="echo fooled"
    guard myalias
    local status=$?
    echo "after"
    return "$status"
  }
  run -"$CG_ERR_NOT_FOUND" --separate-stderr f
  [[ "$output" == *"after"* ]]
  [[ "$stderr" == "[BUG] cg_guard: 'myalias' is an alias"* ]]
}

# bats test_tags=guard
@test "guard returns non-zero from a subshell; caller controls continuation with &&" {
  f() {
    shopt -s expand_aliases
    alias myalias="echo fooled"
    (guard myalias && echo "inside")
    local subshell_status=$?
    echo "subshell=$subshell_status"
    return "$subshell_status"
  }
  run -"$CG_ERR_NOT_FOUND" --separate-stderr f
  [[ "$output" == *"subshell=3"* ]]
  [[ "$output" != *"inside"* ]]
  [[ "$stderr" == "[BUG] cg_guard: 'myalias' is an alias"* ]]
}

# --- Multiple commands support ---

# bats test_tags=guard,pr1
@test "guard accepts multiple commands" {
  f() { guard uname date hostname; }
  run -0 f
}

# bats test_tags=guard,pr1
@test "multiple commands all create wrapper functions" {
  f() {
    guard uname date hostname
    [[ "$(type -t uname)" == "function" ]]
    [[ "$(type -t date)" == "function" ]]
    [[ "$(type -t hostname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr1
@test "multiple guarded commands execute correctly" {
  f() {
    guard uname echo
    local out1 out2
    out1="$(uname)"
    # shellcheck disable=SC2116  # echo is a guarded wrapper here, not the builtin
    out2="$(echo test)"
    [[ -n "$out1" ]]
    [[ "$out2" == "test" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr1,focus
@test "failure in one command stops processing, acts as no-op" {
  f() {
    guard uname nonexistent_xyz date
    echo "EXIT_CODE:$?"
    type -t uname
  }
  run f
  [[ "${lines[0]}" == *"[ERROR] cg_guard: unable to resolve full path"* ]]
  [[ "${lines[1]}" == "EXIT_CODE:3" ]]
  [[ "${lines[2]}" == "file" ]]
}

# bats test_tags=guard,pr1
@test "backward compatible with single command" {
  f() {
    guard uname
    [[ "$(type -t uname)" == "function" ]]
    local out
    out="$(uname)"
    [[ -n "$out" ]]
  }
  run -0 f
}

# --- name=path token syntax ---

# bats test_tags=guard,pr2
@test "guard accepts cmd=path syntax" {
  f() { guard "uname=/usr/bin/uname"; }
  run -0 f
}

# bats test_tags=guard,pr2
@test "custom path command creates wrapper function" {
  f() {
    guard "uname=/usr/bin/uname"
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr2
@test "custom path command executes with specified path" {
  f() {
    guard "kernel=/usr/bin/uname"
    local out
    out="$(kernel -s)"
    [[ -n "$out" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr2
@test "mix of custom path and regular commands" {
  f() {
    guard "uname=/usr/bin/uname" date hostname
    [[ "$(type -t uname)" == "function" ]]
    [[ "$(type -t date)" == "function" ]]
    [[ "$(type -t hostname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr2
@test "custom path with nonexistent file fails" {
  f() { guard "badcmd=/nonexistent/path/badcmd"; }
  run -"$CG_ERR_NOT_FOUND" f
  [[ "$output" == *"unable to resolve"* ]]
}

# bats test_tags=guard,pr2
@test "custom path with non-executable fails" {
  local tmpfile
  tmpfile=$(mktemp)
  f() { guard "notexec=$tmpfile"; }
  run -"$CG_ERR_NOT_FOUND" f
  rm -f "$tmpfile"
}

# bats test_tags=guard,pr2
@test "custom path with relative path fails" {
  f() { guard "cmd=../bin/cmd"; }
  run -"$CG_ERR_SYNTAX_ERROR" f
  [[ "$output" == *"absolute path"* ]]
}

# bats test_tags=guard,pr2
@test "invalid syntax in cmd=path fails gracefully" {
  f() { guard "bad-name=/usr/bin/test"; }
  run -"$CG_ERR_INVALID_NAME" f
  [[ "$output" == *"invalid command identifier"* ]]
}

# --- PATH enforcement: cg_safe_run, cg_unsafe, command_not_found_handle ---

# bats test_tags=guard,cg_safe_run
@test "cg_safe_run executes a guarded function" {
  f() {
    guard uname
    _func() { uname -s; }
    cg_safe_run _func
  }
  run -0 f
  [[ -n "$output" ]]
}

# bats test_tags=guard,cg_safe_run
@test "non-guarded external command fails inside cg_safe_run" {
  f() {
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  }
  run -0 f
  [[ "$output" == *"exit:127"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "cg_unsafe restores writable PATH inside cg_safe_run" {
  f() {
    _init() { cg_unsafe guard uname; }
    _func() { _init; uname -s; }
    cg_safe_run _func
  }
  run -0 f
  [[ -n "$output" ]]
}

# bats test_tags=guard,cg_safe_run
@test "cg_safe_run rejects non-function argument" {
  f() { cg_safe_run not_a_function; }
  run -"$CG_ERR_INVALID_NAME" --separate-stderr f
  [[ "$stderr" == *"[ERROR] cg_safe_run:"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG=1 prints WARNING for non-guarded command" {
  f() {
    CG_DEBUG=1
    nonexistent_cmd_cg_test_xyz
    echo "exit:$?"
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] cg_guard: non-guarded command"* ]]
  [[ "$output" == *"exit:127"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG=1 suggests guard path inside cg_safe_run" {
  f() {
    CG_DEBUG=1
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] Suggestion: cg_guard uname="* ]]
}

# bats test_tags=guard,cg_safe_run
@test "CG_DEBUG unset is silent for non-guarded command" {
  f() {
    unset CG_DEBUG
    _func() { uname; }
    cg_safe_run _func
    echo "exit:$?"
  }
  run -0 --separate-stderr f
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "command_not_found_handle not installed when already defined" {
  # Genuine fresh-shell test: handler must be defined before the library is sourced.
  # The sentinel prevents re-sourcing in the BATS process, so run bash is required.
  # shellcheck disable=SC2016  # $LIB is exported; it expands inside the subprocess, not here
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
  f() {
    CG_DEBUG=1
    command_not_found_handle() {
      echo "APP_HANDLER:$1"
      cg_command_not_found_handler "$@"
    }
    nonexistent_cmd_cg_test_xyz
    echo "exit:$?"
  }
  run -0 --separate-stderr f
  [[ "$output" == *"APP_HANDLER:nonexistent_cmd_cg_test_xyz"* ]]
  [[ "$stderr" == *"[WARNING] cg_guard: non-guarded command"* ]]
}

# bats test_tags=guard,cg_safe_run
@test "guard -r resolver uses provided function for path resolution" {
  f() {
    my_resolver() {
      local cmd="${*: -1}"
      [[ "$cmd" == "uname" ]] || return 3
      printf "/usr/bin/uname"
    }
    guard -r my_resolver uname
    [[ "$(type -t uname)" == "function" ]]
    local out
    out=$(uname)
    [[ -n "$out" ]]
  }
  run -0 f
}

# --- cg_path_resolver -s option ---

# bats test_tags=guard,cg_path_resolver
@test "cg_path_resolver -s resolves a standard command" {
  f() { guard -r cg_path_resolver -s uname; }
  run -0 f
}

# bats test_tags=guard,cg_path_resolver
@test "cg_path_resolver -s fails for unknown command" {
  f() { guard -r cg_path_resolver -s nonexistent_xyz_cg_test; }
  run -"$CG_ERR_NOT_FOUND" f
}

# bats test_tags=guard,cg_path_resolver
@test "cg_path_resolver -d then -s finds command present only in safe path" {
  # /nonexistent_cg_test is not a real dir; uname is not there, but -s adds the safe path
  f() { guard -r cg_path_resolver -d /nonexistent_cg_test -s uname; }
  run -0 f
}

# bats test_tags=guard,cg_path_resolver
@test "cg_path_resolver -s then -d finds command present only in safe path" {
  f() { guard -r cg_path_resolver -s -d /nonexistent_cg_test uname; }
  run -0 f
}

# bats test_tags=guard,cg_path_resolver
@test "cg_path_resolver -d without -s does not find standard command" {
  f() { guard -r cg_path_resolver -d /nonexistent_cg_test uname; }
  run -"$CG_ERR_NOT_FOUND" f
}

# --- Duplicate option rejection ---

# bats test_tags=guard,options
@test "guard rejects duplicate -q" {
  f() { guard -q -q uname; }
  run -"$CG_ERR_SYNTAX_ERROR" --separate-stderr f
  [[ "$stderr" == *"[ERROR] cg_guard: option -q specified more than once."* ]]
}

# bats test_tags=guard,options
@test "guard rejects duplicate -r" {
  f() { guard -r cg_safe_resolver -r cg_safe_resolver uname; }
  run -"$CG_ERR_SYNTAX_ERROR" --separate-stderr f
  [[ "$stderr" == *"[ERROR] cg_guard: option -r specified more than once."* ]]
}

# bats test_tags=guard,options
@test "guard rejects duplicate -p" {
  f() { guard -p foo_ -p bar_ uname; }
  run -"$CG_ERR_SYNTAX_ERROR" --separate-stderr f
  [[ "$stderr" == *"[ERROR] cg_guard: option -p specified more than once."* ]]
}

# --- Unrecognised option rejection (T09) ---

# bats test_tags=guard,options
@test "cg_guard rejects option not recognised by default resolver" {
  f() { cg_guard -x uname; }
  run -"$CG_ERR_SYNTAX_ERROR" --separate-stderr f
  [[ "$stderr" == *"not recognised"* ]]
}

# bats test_tags=guard,options
@test "cg_guard rejects option not recognised by cg_path_resolver" {
  f() { cg_guard -r cg_path_resolver -x uname; }
  run -"$CG_ERR_SYNTAX_ERROR" --separate-stderr f
  [[ "$stderr" == *"not recognised"* ]]
}

# --- Zero commands and options support ---

# bats test_tags=guard,pr4
@test "guard with zero commands emits warning and returns 0" {
  f() { guard; }
  run -0 --separate-stderr f
  [[ "$stderr" == *"[WARNING] cg_guard: no commands specified."* ]]
}

# bats test_tags=guard,pr4
@test "guard with -q suppresses warnings for zero commands" {
  f() { guard -q; }
  run -0 --separate-stderr f
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "guard with -- separates options from commands" {
  f() {
    guard -- uname
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,pr4
@test "guard with -q -- suppresses warnings and separates options" {
  f() {
    guard -q --
    [[ "$(type -t uname)" != "function" ]]
  }
  run -0 --separate-stderr f
  [[ "$stderr" != *"WARNING"* ]]
}

# bats test_tags=guard,pr4
@test "guard backward compatible with single command after options" {
  f() {
    guard -q -- uname
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# --- prefix (-p) option ---

# bats test_tags=guard,prefix
@test "guard -p prefix_ creates prefixed wrapper for plain-name tokens" {
  f() {
    guard -p mylib_ uname date
    [[ "$(type -t mylib_uname)" == "function" ]]
    [[ "$(type -t mylib_date)" == "function" ]]
    [[ "$(type -t uname)" != "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,prefix
@test "guard -p does not apply prefix to fname=path tokens" {
  f() {
    guard -p mylib_ "myuname=/usr/bin/uname"
    [[ "$(type -t myuname)" == "function" ]]
    [[ "$(type -t mylib_myuname)" != "function" ]]
  }
  run -0 f
}

# --- Extended token forms ---

# bats test_tags=guard,tokens
@test "guard fname=name resolves name via active resolver" {
  f() {
    guard "kernel=uname"
    [[ "$(type -t kernel)" == "function" ]]
    local out
    out=$(kernel -s)
    [[ -n "$out" ]]
  }
  run -0 f
}

# bats test_tags=guard,tokens
@test "guard /abs/path creates wrapper with prefixed basename" {
  f() {
    local uname_path
    uname_path="$(PATH=/usr/bin:/bin command -v uname)"
    guard -p mylib_ "$uname_path"
    [[ "$(type -t mylib_uname)" == "function" ]]
    local out
    out=$(mylib_uname)
    [[ -n "$out" ]]
  }
  run -0 f
}

# bats test_tags=guard,tokens
@test "guard fname=name with relative rhs is rejected" {
  f() { guard "mybash=../bin/bash"; }
  run -"$CG_ERR_SYNTAX_ERROR" f
}

# --- Environmental regression tests ---
# These tests verify undocumented Bash behaviors the library relies on.
# No skip — must always pass. A failure indicates a Bash regression that
# would break the library on this platform.

# bats test_tags=guard,envtest
@test "envtest: local VAR in callee shadows local -r VAR from parent without error" {
  f() {
    outer() {
      local -r MYVAR="readonly_value"
      inner
    }
    inner() {
      local MYVAR="writable_value"
      [[ "$MYVAR" == "writable_value" ]]
    }
    outer
  }
  run -0 f
}

# bats test_tags=guard,envtest
@test "envtest: local VAR fails when variable is globally readonly" {
  f() {
    # shellcheck disable=SC2034  # readonly is the point; inner() tries local redeclaration
    readonly GLOBALVAR="fixed"
    inner() { local GLOBALVAR="new_value"; }
    inner
  }
  run f
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
  f() {
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
  }
  run -0 f
  [[ "$output" == *"SEEN_LOCAL_PATH"* ]]
}

# bats test_tags=guard,envtest
@test "envtest: command -pv resolves commands independently of local PATH" {
  f() {
    fake_path_func() {
      local PATH="/nonexistent-fake"
      local result
      result="$(command -pv uname)"
      [[ "$result" == /*/uname ]] && echo "RESOLVED_CORRECTLY"
    }
    fake_path_func
  }
  run -0 f
  [[ "$output" == *"RESOLVED_CORRECTLY"* ]]
}

# bats test_tags=guard,envtest
@test "envtest: eval-defined functions inside functions are globally scoped" {
  f() {
    definer() {
      eval "my_evaled_fn() { echo evaled; }"
    }
    definer
    [[ "$(type -t my_evaled_fn)" == "function" ]]
    my_evaled_fn
  }
  run -0 f
  [[ "$output" == *"evaled"* ]]
}

# --- cg_unsafe outside cg_safe_run (T13) ---

# bats test_tags=guard,cg_unsafe
@test "cg_unsafe outside cg_safe_run is harmless" {
  # cg_unsafe sets local PATH to the compiled-in default. When called outside
  # any cg_safe_run context there is no readonly PATH to shadow, so the local
  # declaration is a no-op and the call succeeds normally.
  f() {
    cg_unsafe cg_guard uname
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# --- _cg_unpack_args (issues #116, #117) ---

# bats test_tags=guard,unpack_args,issue-116
@test "_cg_unpack_args: empty string passes through as one empty element" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args "" || return $?
    [[ "${#_cg_unpacked[@]}" -eq 1 ]] || return $?
    [[ "${_cg_unpacked[0]}" == "" ]]
  }
  run -0 f
}

# bats test_tags=guard,unpack_args,issue-116
@test "_cg_unpack_args: plain word passes through unchanged" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args "prefix_" || return $?
    [[ "${#_cg_unpacked[@]}" -eq 1 ]] || return $?
    [[ "${_cg_unpacked[0]}" == "prefix_" ]]
  }
  run -0 f
}

# bats test_tags=guard,unpack_args,issue-116
@test "_cg_unpack_args: separator-prefixed value splits into elements" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args ":run_:_cb" || return $?
    [[ "${#_cg_unpacked[@]}" -eq 2 ]] || return $?
    [[ "${_cg_unpacked[0]}" == "run_" ]] || return $?
    [[ "${_cg_unpacked[1]}" == "_cb" ]]
  }
  run -0 f
}

# bats test_tags=guard,unpack_args,issue-116
@test "_cg_unpack_args: separator with no content yields empty array" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args ":" || return $?
    [[ "${#_cg_unpacked[@]}" -eq 0 ]]
  }
  run -0 f
}

# bats test_tags=guard,unpack_args,issue-116,issue-117
@test "_cg_unpack_args: x1F-prefixed packed arg splits correctly" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args $'\x1F-d\x1F/snap/bin' || return $?
    [[ "${#_cg_unpacked[@]}" -eq 2 ]] || return $?
    [[ "${_cg_unpacked[0]}" == "-d" ]] || return $?
    [[ "${_cg_unpacked[1]}" == "/snap/bin" ]]
  }
  run -0 f
}

# bats test_tags=guard,unpack_args,issue-117
@test "_cg_unpack_args: x1F alone (snap-absent payload) yields empty array" {
  f() {

    local -a _cg_unpacked
    _cg_unpack_args $'\x1F' || return $?
    [[ "${#_cg_unpacked[@]}" -eq 0 ]]
  }
  run -0 f
}

# --- cg_mkfname_prefix (issue #116) ---

# bats test_tags=guard,mkfname_prefix,issue-116
@test "cg_mkfname_prefix: empty prefix + name yields name" {
  f() {
    local result
    result="$(cg_mkfname_prefix "" "uname" || exit $?)"
    [[ "$result" == "uname" ]]
  }
  run -0 f
}

# bats test_tags=guard,mkfname_prefix,issue-116
@test "cg_mkfname_prefix: non-empty prefix prepended to name" {
  f() {
    local result
    result="$(cg_mkfname_prefix "mylib_" "uname" || exit $?)"
    [[ "$result" == "mylib_uname" ]]
  }
  run -0 f
}

# bats test_tags=guard,mkfname_prefix,issue-116
@test "cg_mkfname_prefix: wrong argument count returns CG_ERR_SYNTAX_ERROR" {
  f() { cg_mkfname_prefix "uname"; }
  run -"$CG_ERR_SYNTAX_ERROR" f
}

# bats test_tags=guard,mkfname_prefix,issue-116
@test "cg_mkfname_prefix: result not a valid identifier returns CG_ERR_INVALID_NAME" {
  f() { cg_mkfname_prefix "bad-" "name"; }
  run -"$CG_ERR_INVALID_NAME" f
}

# --- cg_guard -n custom name filter (issue #116) ---

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -n: custom filter is applied to plain-name tokens" {
  f() {
    my_upper_filter() {
      local prefix="$1" bare="$2"
      printf '%s' "${prefix}${bare}"
    }
    cg_guard -n my_upper_filter -p "ns_" uname || return $?
    unset -f uname
    cg_guard -n my_upper_filter -p "ns_" uname || return $?
    [[ "$(type -t ns_uname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -n: duplicate -n returns CG_ERR_SYNTAX_ERROR with specific message" {
  f() { cg_guard -n cg_mkfname_prefix -n cg_mkfname_prefix uname 2>&1; }
  run -"$CG_ERR_SYNTAX_ERROR" f
  [[ "$output" == *"more than once"* ]]
}

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -n: filter rejection propagates the filter exit code" {
  f() {
    rejecting_filter() { return "$CG_ERR_INVALID_NAME"; }
    cg_guard -n rejecting_filter uname
  }
  run -"$CG_ERR_INVALID_NAME" f
}

# --- cg_guard -p with default filter (issue #116) ---

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -p: empty -p with default filter emits warning" {
  f() { cg_guard -p "" uname 2>&1; }
  run f
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"[WARNING]"* ]]
}

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -p: empty -p with -q suppresses warning" {
  f() {
    declare -f cg_mkfname_prefix >/dev/null 2>&1 || return $?
    cg_guard -q -p "" uname 2>&1
  }
  run -0 f
  [[ "$output" != *"[WARNING]"* ]]
}

# bats test_tags=guard,name_filter,issue-116
@test "cg_guard -p: empty -p with custom -n does not warn" {
  f() {
    my_filter() { printf '%s' "${1}${2}"; }
    cg_guard -n my_filter -p "" uname 2>&1
  }
  run -0 f
  [[ "$output" != *"[WARNING]"* ]]
}

# --- cg_guard -z packed injection (issue #117) ---

# bats test_tags=guard,packed_injection,issue-117
@test "cg_guard -z: packed resolver option is injected and forwarded" {
  f() {
    local tmp
    tmp="$(mktemp -d)"
    cp "$(command -pv uname)" "$tmp/uname"
    cg_guard -r cg_path_resolver "-z:-d:${tmp}" uname || { rm -rf "$tmp"; return 1; }
    unset -f uname
    cg_guard -r cg_path_resolver "-z:-d:${tmp}" uname || { rm -rf "$tmp"; return 1; }
    [[ "$(type -t uname)" == "function" ]]
    rm -rf "$tmp"
  }
  run -0 f
}

# bats test_tags=guard,packed_injection,issue-117
@test "cg_guard -z: empty payload (snap-absent) is a no-op injection" {
  f() {
    unset -f uname
    cg_guard -r cg_path_resolver $'-z\x1F' uname || return $?
    [[ "$(type -t uname)" == "function" ]]
  }
  run -0 f
}

# bats test_tags=guard,packed_injection,issue-117
@test "cg_guard -z: repeated -z injects two independent batches" {
  f() {
    local tmp1 tmp2
    tmp1="$(mktemp -d)"; tmp2="$(mktemp -d)"
    cp "$(command -pv uname)" "$tmp1/uname"
    cp "$(command -pv date)"  "$tmp2/date"
    cg_guard -r cg_path_resolver "-z:-d:${tmp1}" "-z:-d:${tmp2}" uname date \
      || { rm -rf "$tmp1" "$tmp2"; return 1; }
    unset -f uname date
    cg_guard -r cg_path_resolver "-z:-d:${tmp1}" "-z:-d:${tmp2}" uname date \
      || { rm -rf "$tmp1" "$tmp2"; return 1; }
    [[ "$(type -t uname)" == "function" ]] || { rm -rf "$tmp1" "$tmp2"; return 1; }
    [[ "$(type -t date)"  == "function" ]]
    rm -rf "$tmp1" "$tmp2"
  }
  run -0 f
}

# --- cg_search_snaps (issue #117) ---

# bats test_tags=guard,cg_search_snaps,issue-117
@test "cg_search_snaps: snap absent — output is a no-op -z string" {
  f() {
    declare -f cg_search_snaps >/dev/null 2>&1 || return $?
    declare -f _cg_unpack_args  >/dev/null 2>&1 || return $?
    snap() { return 1; }
    local out
    out="$(cg_search_snaps)" || true
    [[ "${out:0:2}" == "-z" ]] || return $?
    local -a _cg_unpacked
    _cg_unpack_args "${out:2}" || return $?
    [[ "${#_cg_unpacked[@]}" -eq 0 ]]
  }
  run -0 f
}

# bats test_tags=guard,cg_search_snaps,issue-117
@test "cg_search_snaps: snap present — output contains -d and the snap bin dir" {
  f() {
    declare -f cg_search_snaps >/dev/null 2>&1 || return $?
    declare -f _cg_unpack_args  >/dev/null 2>&1 || return $?
    local snap_dir
    snap_dir="$(mktemp -d)"
    snap() {
      if [[ "$1 $2" == "debug paths" ]]; then
        printf 'SNAPD_BIN=%s\n' "$snap_dir"
        return 0
      fi
      return 1
    }
    command() {
      if [[ "$1" == "-p" && "$2" == "snap" ]]; then return 0; fi
      builtin command "$@"
    }
    local out
    out="$(cg_search_snaps)" || true
    [[ "${out:0:2}" == "-z" ]] || { rm -rf "$snap_dir"; return 1; }
    local -a _cg_unpacked
    _cg_unpack_args "${out:2}" || { rm -rf "$snap_dir"; return 1; }
    [[ "${#_cg_unpacked[@]}" -eq 2 ]] || { rm -rf "$snap_dir"; return 1; }
    [[ "${_cg_unpacked[0]}" == "-d" ]] || { rm -rf "$snap_dir"; return 1; }
    [[ "${_cg_unpacked[1]}" == "$snap_dir" ]]
    rm -rf "$snap_dir"
  }
  run -0 f
}

# bats test_tags=guard,cg_search_snaps,issue-117
@test "cg_search_snaps: broken snap debug paths — warning emitted, output is no-op" {
  f() {
    declare -f cg_search_snaps >/dev/null 2>&1 || return $?
    declare -f _cg_unpack_args  >/dev/null 2>&1 || return $?
    snap() {
      if [[ "$1 $2" == "debug paths" ]]; then return 1; fi
      return 0
    }
    command() {
      if [[ "$1" == "-p" && "$2" == "snap" ]]; then return 0; fi
      builtin command "$@"
    }
    local warn_file
    warn_file="$(mktemp)"
    local out
    out="$(cg_search_snaps 2>"$warn_file")" || true
    [[ "${out:0:2}" == "-z" ]] || { rm -f "$warn_file"; return 1; }
    local -a _cg_unpacked
    _cg_unpack_args "${out:2}" || { rm -f "$warn_file"; return 1; }
    [[ "${#_cg_unpacked[@]}" -eq 0 ]] || { rm -f "$warn_file"; return 1; }
    grep -q '\[WARNING\]' "$warn_file"
    rm -f "$warn_file"
  }
  run -0 f
}
