---
description: Expert guidance for implementing and using the handle_state.sh Bash library to persist state among a group of library calls from initialization to cleanup, centered on the -S state-variable pattern. Triggers on requests like "pass information", "write initialization function" or "write cleanup function" while developing a library or code module.
---

# Handle State Library Skill

## Core Reference

Use `docs/libraries/handle_state.rst` as the canonical local reference for the
API, warnings, and limitations.

## Quick Workflow

- Source `config/handle_state.sh` once in the main script or library entrypoint.
- Use `hs_extract_token` + `hs_write_token` in entry points to minimize name collision risk.
- In body helpers, call `hs_persist_state -S __mylib_state_token -- <local1> <local2> ...`
  to save state and `hs_read_persisted_state -S __mylib_state_token -- <local1> <local2> ...`
  to restore it. Body helpers hardcode the state variable name because it is a library
  constant declared in the entry-point frame (not user-supplied), and its name is part of
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

### `hs_extract_token` — token extraction for entry points

Two call forms:

**Form 1 — direct query** (`$1 == --list-reserved`):
```bash
hs_extract_token --list-reserved
```
Prints every local in `hs_extract_token`'s own frame, one per line. These are the names
forming the collision surface of this function itself — prohibited as the `-S` argument to
any entry point that delegates to `hs_extract_token`.

**Form 2 — eval form** (`$1` is local name, `${@:2}` are the forwarded args):
```bash
eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
```
The eval form has two operational modes selected automatically by the caller's argument list:

- **Normal mode** (`$2` is not `--list-reserved`): parses `-S <statevar>` from `${@:2}`
  and emits `local __mylib_state_token='<value>'` on success, or `bash -c 'exit N'` on error.

- **Auto `--list-reserved` mode** (`$2 == --list-reserved`): activated when the caller passes
  `--list-reserved` as their first argument, making `$2` of `hs_extract_token` equal to
  `--list-reserved`. Emits two sentinels into the entry-point frame:
  ```bash
  local list_reserved=1
  local __mylib_state_token=''
  ```
  No further arguments (`$3..`) are valid in this mode.

### `hs_write_token` — token write-back for entry points

**Normal eval form**:
```bash
eval "$(hs_write_token __mylib_state_token "$@")" || return $?
```
Parses `-S <statevar>` from `${@:2}` (the forwarded args, which include `-S`) and emits
`<statevar>='<value>'` (plain assignment, not `local`) on success, or `bash -c 'exit N'`
on error. The collision surface depends on the locals declared in the entry-point frame
before this call. When the proper helper pattern has been followed, the token has already
been updated and the surface equals that of `hs_extract_token`.

**`--list-reserved` form** (when `$2 == --list-reserved`):
Prints the function's own frame locals plus `$1` (the source local, which is in the
entry-point's collision space for read-write functions).

Note: `hs_write_token` cannot avoid a name collision if the `-S` state variable and the
source local share a name. This edge case is addressed in issue #139.

## Entry-Point Patterns

### Read-write entry point (restores and persists state)

```bash
mylib_func() {
    eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
    if [[ -z "${list_reserved@A}" ]]; then
        # __mylib_state_token accessible by _mylib_func_body via dynamic scoping.
        # _mylib_func_body calls hs_read_persisted_state -S __mylib_state_token directly.
        _mylib_func_body || return $?
    fi
    # hs_write_token reports the full reserved list (including __mylib_state_token)
    # when --list-reserved is in $@, otherwise writes the token back.
    eval "$(hs_write_token __mylib_state_token "$@")" || return $?
}

_mylib_func_body() {
    local var1 var2
    hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
    # ... work ...
    hs_destroy_state -S __mylib_state_token -- var1 var2 || return $?
    hs_persist_state  -S __mylib_state_token -- var1 var2 || return $?
}
```

### Read-only entry point (restores state, does not persist)

A well-designed read-only entry point has the same collision surface as `hs_extract_token`,
so it delegates `--list-reserved` reporting directly to `hs_extract_token --list-reserved`.

```bash
mylib_ro_func() {
    eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
    [[ -n "${list_reserved@A}" ]] && { hs_extract_token --list-reserved; return 0; }
    _mylib_ro_func_body || return $?
}

_mylib_ro_func_body() {
    local var1 var2
    hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
    # ... read-only work ...
}
```

### Read/modify/write entry point (updates variables inside an existing token)

When a function must mutate variables already stored in a token it received
from its caller, it must destroy those variables before re-persisting them.
`hs_destroy_state` modifies the token immediately, so always pair it with
`hs_persist_state` in the same body helper so a failure aborts before
`hs_write_token` propagates an incomplete token back.

```bash
mylib_update_func() {
    eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
    if [[ -z "${list_reserved@A}" ]]; then
        _mylib_update_func_body || return $?
    fi
    eval "$(hs_write_token __mylib_state_token "$@")" || return $?
}

_mylib_update_func_body() {
    local var1 var2
    hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
    # ... mutate var1, var2 ...
    hs_destroy_state -S __mylib_state_token -- var1 var2 || return $?
    hs_persist_state  -S __mylib_state_token -- var1 var2 || return $?
}
```

### Plain init/cleanup (no entry-point wrapper needed)

```bash
source "$(dirname "$0")/config/handle_state.sh"

mylib_init() {
  local temp_file="/tmp/resource"
  local resource_id="abc123"
  local -a items=(one two three)
  hs_persist_state "$@" -- temp_file resource_id items
}

mylib_cleanup() {
  local temp_file resource_id
  local -a items
  eval "$(hs_read_persisted_state "$@")" || return $?   # implicit form preferred
  rm -f "$temp_file"
  hs_destroy_state "$@" -- temp_file resource_id items
}

local state
mylib_init    -S state
mylib_cleanup -S state
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
| 19 | `HS_ERR_DEPENDENCY_MISSING` | `command_guard.sh` not loadable |

## Safety Notes

- Avoid name collisions when chaining state through a shared state variable; prefer separate
  state variables if libraries overlap variable names.
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
- **To emit results from a subshell**, use the `hs_write_token` eval pattern: inside
  `$(...)` emit `<statevar>='<value>'` to stdout so the caller's `eval` writes the result
  back. On error emit `bash -c 'exit N'` so the caller's `eval` propagates the exit code.
