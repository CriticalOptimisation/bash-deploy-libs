---
description: Expert guidance for implementing and using the handle_state.sh Bash library to persist initialization state to cleanup functions, centered on the -S state-variable pattern. Triggers on requests like "pass information", "write initialization function" or "write cleanup function" while developing a library or code module.
---

# Handle State Library Skill

## Core Reference

Use `docs/libraries/handle_state.rst` as the canonical local reference for the
API, warnings, and limitations.

## Quick Workflow

- Source `config/handle_state.sh` once in the main script or library entrypoint.
- Use `hs_extract_token` + `hs_write_token` in entry points to eliminate nameref collision risk.
- In body helpers, call `hs_persist_state "$@" -- <local1> <local2> ...` to save state and `hs_read_persisted_state "$@" -- <local1> <local2> ...` to restore it.
- New libraries must expose `-S` and must not carry state via stdout.
- The state token is an opaque string assigned to the named variable; never interpret or construct it manually.
- If the same state variable must be reused across several init/cleanup cycles,
  call `hs_destroy_state` before the next init to remove the library's vars from
  the state vector and avoid `HS_ERR_VAR_NAME_COLLISION`.

## Primary Interface

### `hs_persist_state` — serialize locals into the state token

```bash
hs_persist_state "$@" -- var1 var2        # forwarded-args form (preferred)
hs_persist_state -S state_var -- var1     # explicit -S form
hs_persist_state --list-reserved          # print internal reserved names
```

Supports scalars, indexed arrays (`-a`), associative arrays (`-A`), and namerefs
(`-n`). Namerefs: the target variable must be persisted in the same call or
already present in the prior state, otherwise `HS_ERR_NAMEREF_TARGET_NOT_PERSISTED`.

### `hs_read_persisted_state` — restore locals from the state token

Two forms:

**Implicit form** (preferred) — no variable list, emits a restore snippet to stdout:
```bash
eval "$(hs_read_persisted_state "$@")" || return $?
```
Targets only the caller's own unset locals (via `local -p`); cannot pollute global scope.

**Explicit form** — variable names after `--`:
```bash
hs_read_persisted_state "$@" -- var1 var2 || return $?
```
Traverses the full dynamic scope; use when targeting variables in a higher-level caller or declared globals.

Both forms support `-q` to suppress warnings for missing variables.

### `hs_destroy_state` — remove variables from the state token

```bash
hs_destroy_state "$@" -- var1 var2 || return $?
```
Removes named entries from the state vector. Required before re-initializing against the same token.

### `hs_extract_token` — zero-collision token extraction for entry points

Three call forms depending on position of `--list-reserved`:

**Form 1 — direct query** (`$1 == --list-reserved`):
```bash
hs_extract_token --list-reserved
```
Prints every local in `hs_extract_token`'s own frame, one per line.

**Form 2 — normal eval form** (`$1` is local name, `$2..` are forwarded args):
```bash
eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
```
Runs in a subshell. Parses `-S <statevar>` from forwarded args and emits
`local <local_name>='<value>'` on success or `bash -c 'exit N'` on error.
Collision space at fork: zero.

**Form 3 — eval-code `--list-reserved`** (`$1` is local name, `$2 == --list-reserved`, `$3..` are forwarded args):
```bash
eval "$(hs_extract_token __mylib_state_token --list-reserved "$@")" || return $?
```
When `--list-reserved` appears in `$3..`, emits two sentinels:
```bash
local list_reserved=1
local __mylib_state_token=''
```
If absent, falls through to Form 2 using `$3..` as the argument list.

### `hs_write_token` — zero-collision token write-back for entry points

**Normal eval form**:
```bash
eval "$(hs_write_token __mylib_state_token "$@")" || return $?
```
Runs in a subshell. Parses `-S <statevar>` from forwarded args and emits
`<statevar>=<value>` (plain assignment, not `local`) on success or `bash -c 'exit N'` on error.

**`--list-reserved` form** (when `$2 == --list-reserved`):
Emits a `printf` statement that, when `eval`ed, prints the function's own frame
locals plus `$1` (the source local — which is in the entry-point's collision space).

## Entry-Point Patterns

### Read-write entry point (restores and persists state)

```bash
my_func() {
    eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
    if ! _hs_local_exists "$(local -p)" list_reserved; then
        _my_func_body "$@" || return $?
    fi
    eval "$(hs_write_token __mylib_state_token "$@")" || return $?
}

_my_func_body() {
    local var1 var2
    hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
    # ... work ...
    __mylib_state_token=""
    hs_persist_state -S __mylib_state_token -- var1 var2 || return $?
}
```

### Read-only entry point (restores state, does not persist)

```bash
my_ro_func() {
    eval "$(hs_extract_token __mylib_state_token --list-reserved "$@")" || return $?
    if _hs_local_exists "$(local -p)" list_reserved; then
        local lp_snapshot="$(local -p)"
        _hs_print_reserved_names "$lp_snapshot" list_reserved
        return 0
    fi
    _my_ro_func_body "$@" || return $?
}
```

### Read/modify/write entry point (updates variables inside an existing token)

When a function must mutate variables already stored in a token it received
from its caller, it must destroy those variables before re-persisting them.
`hs_destroy_state` modifies the token immediately, so always pair it with
`hs_persist_state` in the same body helper so a failure aborts before
`hs_write_token` propagates an incomplete token back.

```bash
my_update_func() {
    eval "$(hs_extract_token __mylib_state_token "$@")" || return $?
    _my_update_func_body "$@" || return $?
    eval "$(hs_write_token __mylib_state_token "$@")" || return $?
}

_my_update_func_body() {
    local var1 var2
    hs_read_persisted_state -S __mylib_state_token -- var1 var2 || return $?
    # ... mutate var1, var2 ...
    hs_destroy_state -S __mylib_state_token -- var1 var2 || return $?
    hs_persist_state -S __mylib_state_token -- var1 var2 || return $?
}
```

### Plain init/cleanup (no entry-point wrapper needed)

```bash
source "$(dirname "$0")/config/handle_state.sh"

init_function() {
  local temp_file="/tmp/resource"
  local resource_id="abc123"
  local -a items=(one two three)
  hs_persist_state "$@" -- temp_file resource_id items
}

cleanup_function() {
  local temp_file resource_id
  local -a items
  eval "$(hs_read_persisted_state "$@")" || return $?
  rm -f "$temp_file"
  hs_destroy_state "$@" -- temp_file resource_id items
}

local state
init_function -S state
cleanup_function -S state
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

- `hs_persist_state` and `hs_read_persisted_state` use `eval` internally; treat state tokens as trusted input only.
- Avoid name collisions when chaining state through a shared state variable; prefer separate state variables if libraries overlap variable names.
- Do not require stdout to carry state as part of a library API; reserve stdout for normal user-visible output.
- `hs_read_persisted_state` (implicit form) uses `local -p` to restrict restore to the immediate caller's own unset locals — this is the safe default. Use the explicit form only when you need to target higher-scope variables.
- **Subshells cannot update the parent shell's token.** A `$(...)` command substitution or `( )` subshell group inherits a copy of the parent environment. Any `hs_persist_state` call inside a subshell writes only into that copy; the parent's token variable is never modified. Functions that run in a subshell cannot advance library state even if they call `hs_persist_state` successfully. Design stateful code paths to run directly in the shell process, not inside command substitutions.
