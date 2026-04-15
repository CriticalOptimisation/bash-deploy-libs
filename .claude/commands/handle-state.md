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
  variables holding the state, then call `hs_persist_state_as_code -S <state_var> <local1> <local2> ...`.
- Future libraries using `handle_state` are only required to support `-S`.
- The state snippet is assigned directly to the specified variable; do not rely on stdout emission as part of a library API.
- Pass the state variable to cleanup or any API function which needs state information.
- In cleanup, declare locals with the same names, then `eval "$state"`.
- If the same state variable must be reused across several init/cleanup cycles,
  provide a matching state-destruction path that removes the library's vars
  from the state vector before the next init.
- Call `hs_cleanup_output` when done to stop the logging reader.

## Standard Pattern

```bash
source "$(dirname "$0")/config/handle_state.sh"

state_producer() {
  local _state_var=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -S) shift; _state_var=$1; shift ;;
      *) echo "[ERROR] state_producer: unknown option '$1'" >&2; return 1 ;;
    esac
  done

  [[ -n "$_state_var" ]] || {
    echo "[ERROR] state_producer: missing required -S <state_var>" >&2
    return 1
  }

  local temp_file="/tmp/resource"
  local resource_id="abc123"
  hs_persist_state_as_code -S "$_state_var" temp_file resource_id
}

state_consumer() {
  local temp_file resource_id
  eval "$1"
  rm -f "$temp_file"
  echo "Cleaned $resource_id"
}

state_destroyer() {
  local _state_var=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|-S)
        # Same option shape as hs_persist_state_as_code; implementation is expected to
        # delegate to a future hs_destroy_state helper.
        break
        ;;
      *)
        echo "[ERROR] state_destroyer: unknown option '$1'" >&2
        return 1
        ;;
    esac
  done

  hs_destroy_state "$@" temp_file resource_id
}

local state
state_producer -S state
state_consumer "$state"
state_destroyer -S state
state_producer -S state
```

**API Documentation Note**: New libraries should expose `-S` directly and are not required to preserve the older stdout-based calling convention. If a function both consumes and produces state, it can still use `hs_persist_state_as_code -S <var>` internally after processing its own arguments.

The same function can begin by consuming some state and terminate producing some other state.
If it uses the `-s <$state>` option to `hs_persist_state_as_code`, that function can append to the
supplied state vector rather than producing a new one.

When a library needs to reinitialize against the same state variable after
cleanup, document a companion `state_destroyer` pattern. Its syntax should
match `hs_persist_state_as_code`, but its implementation should rely on a future
`hs_destroy_state` helper to remove the listed variables from the state vector
before the next producer call. This avoids collision errors from repeated
`hs_persist_state_as_code` calls on the same state variable.

## Supported Variables

- Only local scalar variables (strings or numbers) are reliably preserved.
- Encode any other state variable as a string. See encoding templates in
  `.github/skills/handle-state/references/templates.md`.
- Always re-declare the same locals in cleanup before `eval`.

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

- `hs_persist_state_as_code` and `hs_read_persisted_state` rely on `eval`; treat state
  strings as trusted input only.
- Avoid name collisions when chaining state snippets; prefer separate state
  strings if libraries overlap variable names.
- Do not require stdout to carry state as part of a new library API; reserve stdout for normal user-visible output.
