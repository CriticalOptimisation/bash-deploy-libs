---
name: handle-state
description: Expert guidance for implementing and using the handle_state.sh Bash library to persist initialization state to cleanup functions, including hs_persist_state usage, logging FIFO setup, and limitations/workarounds for unsupported variable types. Triggers on requests like "pass information", "write initialization function" or "write cleanup function" while developing a library or code module.
---

# Handle State Library Skill

## Core Reference

Use `docs/libraries/handle_state.rst` as the canonical local reference for the
API, warnings, and limitations.

## Quick Workflow

- Source `config/handle_state.sh` once in the main script or library entrypoint.
- In init/setup or wherever the state information is created, define local scalar 
  variables holding the state, then call `hs_persist_state <var_name> ...`.
- Capture the emitted state string from stdout (e.g., `state=$(init)`), and pass
  it to cleanup or any API function which needs state information.
- In cleanup, declare locals with the same names, then `eval "$state"`.
- Call `hs_cleanup_output` when done to stop the logging reader.

## Standard Pattern

.. code-block:: bash

   source "$(dirname "$0")/config/handle_state.sh"

   state_producer() {
     hs_echo "Starting init"
     local temp_file="/tmp/resource"
     local resource_id="abc123"
     hs_persist_state temp_file resource_id
   }

   state_consumer() {
     local temp_file resource_id
     eval "$1"
     rm -f "$temp_file"
     echo "Cleaned $resource_id"
   }

   state=$(init)
   cleanup "$state"

The same function can begin by consuming some state and terminate producing some other state. 
If it uses the ``-s <$state>`` option to ``hs_persist_state``, that function can append to the
supplied state vector rather than producing a new one. The benefits of either option depend on 
the use case and must be decided by analysis, but in general a library should have only one
state vector unless its purpose implies the production of several similar state vectors.

## Logging FIFO Guidance

- `hs_setup_output_to_stdout` runs on source; it redirects `hs_echo` output to
  the main stdout even when init runs inside `$(...)`.
- Use `hs_echo` inside init functions when stdout is reserved for the state
  snippet.
- Do not write to stdout directly in init; it will corrupt the state string.

## Supported Variables

- Only local scalar variables (strings or numbers) are reliably preserved.
- Encode any other state variable as a string. Use appropriate template from [references/templates.md](references/templates.md)
- Always re-declare the same locals in cleanup before `eval`.

## Known Limitations (Tracked)

The following behaviors are tracked in GitHub; avoid them or apply workarounds.

- Unknown variable names are silently ignored:
  `Issue #1 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/1>`_.
- Function names are silently ignored:
  `Issue #2 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/2>`_.
- Indexed arrays only preserve the first element (major):
  `Issue #3 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/3>`_.
- Associative arrays are silently ignored:
  `Issue #4 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/4>`_.
- Namerefs are persisted as scalars (indirection is lost):
  `Issue #5 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/5>`_.

## Workarounds

- Represent associative arrays as two indexed arrays (keys and values).
- Represent indexed arrays as a single scalar string (encode/decode) or as an
  associative array if appropriate.
- Convert other complex constructs into strings and rebuild them in cleanup.

## Safety Notes

- `hs_persist_state` and `hs_read_persisted_state` rely on `eval`; treat state
  strings as trusted input only.
- Avoid name collisions when chaining state snippets; prefer separate state
  strings if libraries overlap variable names.
