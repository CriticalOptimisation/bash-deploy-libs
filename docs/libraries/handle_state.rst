Handle State Library
====================

Location
--------

- `config/handle_state.sh`

Purpose
-------

This library provides two core capabilities for Bash libraries:

- Persisting local variable state from one function to another (typically
  initialization to cleanup) via a generated snippet that can be `eval`'d.
- As its state persistence functions output code on stdout, the library allows
  provides the means to display messages to stdout from within initialization 
  functions using a logging FIFO and background reader process.

Dependencies
------------

This library depends on the Command Guard Library (`config/command_guard.sh`)
for secure execution of external commands. The dependency is automatically
resolved when the library is sourced.

Quick Start
-----------

Source the file once, then use `hs_persist_state` in the init function and
`eval` the state in cleanup.

.. code-block:: bash

   # Source once in the main script of your library
   source "$(dirname "$0")/config/handle_state.sh"

   init_function() {
       # Direct output to stdout would mess up the state snippet, so use hs_echo if needed
       hs_echo "Initializing..."
       # Define some opaque library resources
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

   # Capture the opaque state snippet emitted on stdout
   state=$(init_function)  
   # Your main script logic here
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

  .. warning::
    This library allocates a new, unused file descriptor for internal job operations.
    While this descriptor will not interfere with any file descriptors already in use,
    please note that file descriptors are a global resource. The library will break down
    if downstream code attempts to use or manipulate its private file descriptor.

hs_cleanup_output
~~~~~~~~~~~~~~~~~

Defined dynamically by `hs_setup_output_to_stdout`. Sends the kill token to the
FIFO, waits for the background reader to exit, and redefines itself as a no-op
while resetting `hs_echo` to a plain `echo`.

hs_echo
~~~~~~~

Defined dynamically by `hs_setup_output_to_stdout`. Writes messages to the FIFO
so they appear in the main script stdout even when stdout of a subshell is being captured.

- Usage: `hs_echo "message"`
- Notes: preserves Bash echo argument concatenation behavior.

hs_persist_state
~~~~~~~~~~~~~~~~

Emits Bash code that restores specified local variables in a receiving scope.
The emitted snippet only assigns values if the target variable is declared
`local` in the receiving scope and is still empty.

The function accepts an optional `-s "$state"` argument to provide an existing
state snippet. Libraries are encouraged to provide the same option to their
initialization functions to allow callers to chain state snippets together.

When appending to an existing state snippet, the function checks for name collisions
and refuses to overwrite existing variables. Some library combinations can be 
incompatible with the chaining approach because they use overlapping variable names.
The alternate solution is to keep and eval separate state snippets for each library.

- Usage: `hs_persist_state [-s "$state"] var1 var2 ...`
- Output: a string of Bash code intended to be `eval`'d by the caller.
- Errors:
  - Refuses to persist reserved names `__var_name` and `__existing_state`.
  - Rejects collisions when a variable already exists in the provided state.

hs_read_persisted_state
~~~~~~~~~~~~~~~~~~~~~~~

This function is a simple wrapper around `echo`. There is no way in Bash to
set variables in the caller scope without `eval`ing code, so this function
is only provided for symmetry with `hs_persist_state`. Its output must be
`eval`'d by the caller to restore state anyway and the effect is identical to
`eval "$state"`. Code readability is slightly improved by using this function.

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

Supported Variables
-------------------

`hs_persist_state` reliably preserves local scalar variables (strings or numbers)
that are defined in the calling scope and re-declared as `local` in the receiving
scope.

Known Limitations (Tracked)
---------------------------

The following behaviors are tracked in GitHub and should be considered when
using this library:

- Unknown variable names are silently ignored instead of erroring:
  `Issue #1 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/1>`_.
- Function names are silently ignored instead of erroring:
  `Issue #2 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/2>`_.
- Indexed arrays only preserve the first element (marked major):
  `Issue #3 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/3>`_.
- Associative arrays are silently ignored:
  `Issue #4 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/4>`_.
- Namerefs are persisted as scalars (indirection is lost):
  `Issue #5 <https://github.com/CriticalOptimisation/bash-deploy-libs/issues/5>`_.

Workarounds
-----------

- Associative arrays can be represented as two indexed arrays (keys and values).
- Indexed arrays can be represented as a string with encoding.
- Other complex constructs can sometimes be replaced by scalar strings or rebuilt
  from scalars using custom logic.

.. code-block:: bash
  # In the init function
  local -a myarray=("value1" "value2" "value with spaces"
  encoded=$(printf '%s\0' "${myarray[@]}" | base64 -w0)
  hs_persist_state encoded
  # In the cleanup function
  local encoded
  eval "$(hs_read_persisted_state "$1")"
  declare -a newarray
  mapfile -d '' -t newarray < <(printf '%s' "$encoded" | base64 -d)
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
