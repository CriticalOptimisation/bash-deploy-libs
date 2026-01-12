Handle State Library
====================

Location
--------

- `config/handle_state.sh`

Purpose
-------

This library provides two core capabilities for Bash scripts:

- Persisting local variable state from one function to another (typically
  initialization to cleanup) via a generated snippet that can be `eval`'d.
- Capturing output from subshells (including `$(...)` command substitutions)
  and redirecting it to the main script output stream via a FIFO.

Quick Start
-----------

Source the file once, then use `hs_persist_state` in the init function and
`eval` the state in cleanup.

.. code-block:: bash

   # Source once in your main script
   source "$(dirname "$0")/config/handle_state.sh"

   init_function() {
       local temp_file="/tmp/some_temp_file"
       local resource_id="resource_123"
       hs_persist_state temp_file resource_id
   }

   cleanup() {
       local temp_file resource_id
       eval "$1"
       rm -f "$temp_file"
       echo "Cleaned up resource: $resource_id"
   }

   state=$(init_function)
   cleanup "$state"

Public API
----------

hs_setup_output_to_stdout
~~~~~~~~~~~~~~~~~~~~~~~~~

Sets up a FIFO and background reader process that forwards log lines from
subshells to the main script output. The function initializes internal state,
creates `hs_cleanup_output`, and defines `hs_echo` for use inside subshells.

- Behavior: no-op if logging is already set up (detected via
  `hs_get_pid_of_subshell`).
- Side effects: creates a FIFO via a temporary file, opens it on a file
  descriptor, and removes the FIFO path while the descriptor remains open.

hs_cleanup_output
~~~~~~~~~~~~~~~~~

Defined dynamically by `hs_setup_output_to_stdout`. Sends the kill token to the
FIFO, waits for the background reader to exit, and redefines itself as a no-op
while resetting `hs_echo` to a plain `echo`.

hs_echo
~~~~~~~

Defined dynamically by `hs_setup_output_to_stdout`. Writes messages to the FIFO
so they appear in the main script output even when called from subshells.

- Usage: `hs_echo "message"`
- Notes: preserves Bash echo argument concatenation behavior.

hs_persist_state
~~~~~~~~~~~~~~~~

Emits Bash code that restores specified local variables in a receiving scope.
The emitted snippet only assigns values if the target variable is declared
`local` in the receiving scope and is still empty.

- Usage: `hs_persist_state var1 var2` or `hs_persist_state -s "$state" var1`
- Output: a string of Bash code intended to be `eval`'d by the caller.
- Errors:
  - Refuses to persist reserved names `__var_name` and `__existing_state`.
  - Rejects collisions when a variable already exists in the provided state.

hs_read_persisted_state
~~~~~~~~~~~~~~~~~~~~~~~

Prints a previously generated state snippet without evaluating it. This allows
callers to `eval` the snippet within their own scope (where locals are declared).

- Usage: `eval "$(hs_read_persisted_state "$state")"`

hs_get_pid_of_subshell
~~~~~~~~~~~~~~~~~~~~~~

Parses the `hs_cleanup_output` function definition to extract the background
reader PID. This is used to detect whether logging setup has already occurred.

Error Codes
-----------

- `HS_ERR_RESERVED_VAR_NAME=1`: a reserved variable name was passed to
  `hs_persist_state`.
- `HS_ERR_VAR_NAME_COLLISION=2`: the requested variable was already defined in
  the state string when persisting.

Behavior Details
----------------

Logging FIFO
~~~~~~~~~~~~

When sourced, the library calls `hs_setup_output_to_stdout` automatically. It
spawns a background reader that:

- reads lines from the FIFO with a timeout loop,
- echoes them to stdout,
- exits after a magic kill token or an idle timeout,
- closes the FIFO descriptor before exiting.

State Persistence
~~~~~~~~~~~~~~~~~

`hs_persist_state` captures caller-local variables by name, embeds their values
in a guarded assignment snippet, and prints that snippet. The guards ensure that
only `local` variables are populated in the receiving scope and that non-empty
locals are not overwritten.

Caveats
-------

- Always declare target variables `local` before `eval`'ing the state snippet;
  otherwise assignments are skipped to avoid leaking globals.
- The library uses `eval` internally; treat state strings as trusted input.
- Call `hs_cleanup_output` when you are done to stop the background reader.

Source Listing
--------------

.. literalinclude:: ../../config/handle_state.sh
   :language: bash
   :linenos:
