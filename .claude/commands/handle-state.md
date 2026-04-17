---
description: Expert guidance for implementing and using the handle_state.sh Bash library to persist initialization state to cleanup functions, centered on the -S state-variable pattern and limitations/workarounds for unsupported variable types. Triggers on requests like "pass information", "write initialization function" or "write cleanup function" while developing a library or code module.
---

# Handle State Library Skill

## Core Reference

Use `docs/libraries/handle_state.rst` as the canonical local reference for the
API, warnings, and limitations.

## Quick Workflow

- Source `config/handle_state.sh` once in the main script or library entrypoint.
- In init/setup or wherever the state information is created, define local scalar
  variables holding the state, then call
  `hs_persist_state_as_code "$@" -- <local1> <local2> ...`.
- Future libraries using `handle_state` are only required to support `-S`.
- The state snippet is assigned directly to the specified variable; stdout-based state transport is obsolete and should not be supported in library APIs.
- Pass the state variable to cleanup or any API function which needs state information.
- In cleanup, restore the needed locals with `hs_read_persisted_state "$@" -- <local1> <local2> ...`.
- If the same state variable must be reused across several init/cleanup cycles,
  provide a matching state-destruction path that removes the library's vars
  from the state vector before the next init.

## Standard Pattern

```bash
source "$(dirname "$0")/config/handle_state.sh"

init_function() {
  local temp_file="/tmp/resource"
  local resource_id="abc123"
  hs_persist_state_as_code "$@" -- temp_file resource_id
}

cleanup_function() {
  local temp_file resource_id
  hs_read_persisted_state "$@" -- temp_file resource_id
  rm -f "$temp_file"
  echo "Cleaned $resource_id"
  hs_destroy_state "$@" -- temp_file resource_id
}

local state
init_function -S state
cleanup_function -S state
init_function -S state
```

**API Documentation Note**: New libraries should expose `-S` directly and should not preserve the older stdout-based calling convention. Pass the full parameter set to `hs_persist_state_as_code`, `hs_read_persisted_state`, and `hs_destroy_state`, then use `--` as the separator before the list of local variable names.

When a library needs to reinitialize against the same state variable after
cleanup, the cleanup function must call `hs_destroy_state` to remove the
library's variables from the state vector before the next init call. This
avoids collision errors from repeated `hs_persist_state_as_code` calls on the
same state variable.

If a library function consumes some of its own arguments before calling
`handle_state`, preserve the remaining parameter list and still pass the full
residual `"$@"` to the helper. Use `--` before the local variable list so
future helper options cannot collide with local variable names or parameter
values. The last `--` is the effective separator; earlier ones may belong to the
library's own API.

## Supported Variables

- Only local scalar variables (strings or numbers) are reliably preserved.
- Encode any other state variable as a string. See encoding templates in
  `.github/skills/handle-state/references/templates.md`.
- Re-declare the same locals in cleanup before `hs_read_persisted_state`.

## Known Limitations (Tracked)

The following behaviors are tracked in GitHub; avoid them or apply workarounds.

- Unknown variable names are silently ignored (Issue #1).
- Function names are silently ignored (Issue #2).
- Indexed arrays only preserve the first element — major (Issue #3).
- Associative arrays are silently ignored (Issue #4).
- Namerefs are persisted as scalars, indirection is lost (Issue #5).

## Workarounds

- Represent associative arrays as two indexed arrays (keys and values).
- Represent indexed arrays as a single scalar string (encode/decode) or as an
  associative array if appropriate.
- Convert other complex constructs into strings and rebuild them in cleanup.
- See `.github/skills/handle-state/references/templates.md` for encoding examples.

## Safety Notes

- Avoid direct `eval` of the raw state string in new library code.
- `hs_persist_state_as_code` and `hs_read_persisted_state` still rely on `eval`
  internally; treat state strings as trusted input only.
- Avoid name collisions when chaining state through a shared state variable; prefer separate state
  variables if libraries overlap variable names.
- Do not require stdout to carry state as part of a library API; reserve stdout for normal user-visible output.
