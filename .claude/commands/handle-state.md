---
description: Expert guidance for implementing and using the handle_state.sh Bash library to persist state among a group of library calls from initialization to cleanup, centered on the -S state-variable pattern. Triggers on requests like "pass information", "write initialization function" or "write cleanup function" while developing a library or code module.
---

# Handle State Library Skill

## Core Reference

Use `docs/libraries/handle_state.rst` as the canonical local reference for the
API, warnings, and limitations.

> **IMPORTANT:** Never call `_hs_*` or `__hs_*` internal functions from library code or
> documentation examples. Do not read the library source to infer behavior — use only the
> documented public API.

## Quick Workflow

- Source `config/handle_state.sh` once in the main script or library entrypoint.
- Wrap entry points in the single skeleton (`hs_extract_token` → `hs_is_list_reserved_mode` guard
  → `hs_finalize_token`) to minimize name collision risk.
- In body helpers, call `hs_persist_state -S __mylib_state_token -- <local1> <local2> ...`
  to save state and `hs_read_persisted_state -S __mylib_state_token -- <local1> <local2> ...`
  to restore it. Body helpers hardcode the state variable name because it is a library
  constant defined in the entry-point frame (not user-defined), and its name is part of
  the calling convention of the helper.
- New libraries must expose `-S` and must not carry state via stdout.
- The state token is an opaque string assigned to the named variable; never interpret or
  construct it manually.
- If the same state variable must be reused across several init/cleanup cycles,
  call `hs_destroy_state` before the next init to remove the library's vars from
  the state vector and avoid `HS_ERR_VAR_NAME_COLLISION`.
- In a library, call `hs_destroy_state -S __mylib_state_token -- var1 var2 ...` from the
  cleanup function to expunge all state variables declared by init or any other library
  function. The token must be fully cleared before the cleanup function returns.

## Primary Interface

### `hs_persist_state` — serialize locals into the state token

```bash
hs_persist_state -S __mylib_state_token -- var1 var2   # explicit -S (preferred in body helpers)
hs_persist_state "$@" -- var1 var2                      # forwarded-args form (entry-point delegation)
hs_persist_state --list-reserved                        # print internal reserved names
```

Supports scalars, indexed arrays (`-a`), associative arrays (`-A`), and namerefs
(`-n`). Namerefs: the target variable must be persisted in the same call or
already present in the prior state, otherwise `HS_ERR_NAMEREF_TARGET_NOT_PERSISTED`.

### `hs_read_persisted_state` — restore locals from the state token

Two forms:

**Implicit form** (preferred) — no variable list, emits a restore snippet to stdout:
```bash
eval "$(hs_read_persisted_state -S __mylib_state_token)" || return $?
```
Targets only the caller's own unset locals (via `local -p`); cannot pollute global scope.

**Explicit form** — variable names after `--`:
```bash
hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
```
Traverses the full dynamic scope; use when targeting variables in a higher-level caller or
declared globals.

Both forms support `-q` to suppress warnings for missing variables.

### `hs_destroy_state` — remove variables from the state token

```bash
hs_destroy_state -S __mylib_state_token -- var1 var2 || return $?
```
Removes named entries from the state vector. Required before re-initializing against the
same token.

### `hs_extract_token` — populate the entry-point token local

```bash
eval "$(hs_extract_token mylib_func __mylib_state_token "$@")" || return $?
hs_extract_token --list-reserved     # direct query: own reserved names
```
Normal mode extracts the `-S` state into the token local (`-S` mandatory). With `--list-reserved`
in the caller's args it mints a mode token (`HS2:mode=list-reserved:…`) carrying the reserved-name
surface. See RST `hs_extract_token`.

### `hs_finalize_token` — finalize the entry point (always the last line)

```bash
eval "$(hs_finalize_token mylib_func __mylib_state_token "$@")" || return $?
```
Replaces `hs_write_token`. Token-driven: writes a normal token back to `-S` (nothing if no `-S`),
or emits the collision report for a mode token. See RST `hs_finalize_token`.

### `hs_is_list_reserved_mode` — body-skip guard

```bash
hs_is_list_reserved_mode -S __mylib_state_token || { _mylib_func "$@" || return $?; }
```
True iff the token is a list-reserved mode token. See RST `hs_is_list_reserved_mode`.

### `hs_read_only` — optional read-only marker (read-only entry points only)

```bash
eval "$(hs_read_only mylib_func __mylib_state_token "$@")"
```
Strips `-S` from `$@` (normal token) or appends `-ro` to the mode marker, so `hs_finalize_token`
does no write-back and excludes the token local. See RST `hs_read_only`.

## Entry-Point Pattern

One skeleton for every stateful entry point (read-write, read/modify/write, read-only):

```bash
mylib_func() {
    eval "$(hs_extract_token  mylib_func __mylib_state_token "$@")" || return $?
    # eval "$(hs_read_only    mylib_func __mylib_state_token "$@")"   # <-- uncomment iff read-only
    hs_is_list_reserved_mode -S __mylib_state_token || { _mylib_func "$@" || return $?; }
    eval "$(hs_finalize_token mylib_func __mylib_state_token "$@")" || return $?
}
```
The body helper `_mylib_func` does the `hs_read_persisted_state` / `hs_destroy_state` /
`hs_persist_state` work (read-only helpers omit destroy/persist). Full patterns, body-helper
examples, and `--list-reserved` output rules: see RST **Entry-Point Pattern**.

### Plain init/cleanup (no entry-point wrapper needed)

```bash
source "$(dirname "$0")/config/handle_state.sh"

mylib_init() {
  local mylib_temp_file="/tmp/resource"
  local mylib_resource_id="abc123"
  local -a mylib_items=(one two three)
  hs_persist_state "$@" -- mylib_temp_file mylib_resource_id mylib_items
}

mylib_cleanup() {
  local mylib_temp_file mylib_resource_id
  local -a mylib_items
  eval "$(hs_read_persisted_state "$@")" || return $?   # implicit form preferred
  rm -f "$mylib_temp_file"
  hs_destroy_state "$@" -- mylib_temp_file mylib_resource_id mylib_items
}

local mylib_state
mylib_init    -S mylib_state
mylib_cleanup -S mylib_state
```

## Supported Variable Types

All Bash variable types are supported:
- **Scalars** (string/integer) — fully supported
- **Indexed arrays** (`local -a`) — fully supported; all elements round-trip
- **Associative arrays** (`local -A`) — fully supported
- **Namerefs** (`local -n`) — fully supported; the nameref target must be
  persisted in the same call or already present in the prior state
  (`HS_ERR_NAMEREF_TARGET_NOT_PERSISTED` otherwise)

## Error Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 1 | `HS_ERR_RESERVED_VAR_NAME` | Name starts with `__hs_` |
| 2 | `HS_ERR_VAR_NAME_COLLISION` | Name already present in state |
| 3 | `HS_ERR_MULTIPLE_STATE_INPUTS` | `-S` given more than once |
| 4 | `HS_ERR_CORRUPT_STATE` | State not in HS2 format or checksum mismatch |
| 5 | `HS_ERR_INVALID_VAR_NAME` | Not a valid Bash identifier |
| 6 | `HS_ERR_VAR_NAME_NOT_IN_STATE` | Requested name absent from state |
| 7 | `HS_ERR_STATE_VAR_UNINITIALIZED` | `-S` var is unset or empty |
| 8 | `HS_ERR_MISSING_ARGUMENT` | `-S` not supplied |
| 9 | `HS_ERR_INVALID_ARGUMENT_TYPE` | Wrong argument type |
| 10 | `HS_ERR_UNKNOWN_VAR_NAME` | Name not declared in scope, or is a function |
| 11 | `HS_ERR_VAR_ALREADY_SET` | Explicit restore target is already set |
| 12 | `HS_ERR_NAMEREF_TARGET_NOT_PERSISTED` | Nameref target not in state |
| 13 | `HS_ERR_LIST_RESERVED_TOKEN` | Mode token (`mode=…`) passed to a normal state consumer |
| 19 | `HS_ERR_DEPENDENCY_MISSING` | `command_guard.sh` not loadable |

## Safety Notes

- Think of a state variable as a session with a library. Mixing libraries into one
  session exposes the caller to name collisions between libraries from different sources;
  prefer separate state variables per library.
- Do not require stdout to carry state as part of a library API; reserve stdout for normal
  user-visible output.
- `hs_read_persisted_state` (implicit form) uses `local -p` to restrict restore to the
  immediate caller's own unset locals — this is the safe default. Use the explicit form
  only when you need to target higher-scope variables.
- **Subshells cannot update the parent shell's token.** A `$(...)` command substitution or
  `( )` subshell group inherits a copy of the parent environment. Any `hs_persist_state`
  call inside a subshell writes only into that copy; the parent's token variable is never
  modified. Functions that run in a subshell cannot advance library state even if they call
  `hs_persist_state` successfully. Design stateful code paths to run directly in the shell
  process, not inside command substitutions.
- **To emit results from a subshell**, use the `hs_finalize_token` eval pattern: inside
  `$(...)` emit `<statevar>='<value>'` to stdout so the caller's `eval` writes the result
  back. On error emit `bash -c 'exit N'` so the caller's `eval` propagates the exit code.
  Example:
  ```bash
  my_subshell_func() {
      # runs inside $(...)
      local result="computed-value"
      printf '%s=%s\n' "$1" "$(printf '%q' "$result")"
  }
  eval "$(my_subshell_func __mylib_state_token)" || return $?
  ```
