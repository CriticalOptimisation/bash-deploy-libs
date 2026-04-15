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

Source the file once, then use `hs_persist_state_as_code` in the init function and
`eval` the state in cleanup. For cleaner code, assign to a variable instead of
capturing stdout.

.. code-block:: bash

   # Source once in the main script of your library
   source "$(dirname "$0")/config/handle_state.sh"

   init_function() {
       # Direct output to stdout would mess up the state snippet, so use hs_echo if needed
       hs_echo "Initializing..."
       # Define some opaque library resources
       local temp_file="/tmp/some_temp_file"
       local resource_id="resource_123"
       hs_persist_state_as_code "$@" temp_file resource_id
   }

   cleanup() {
       local state="$1"
       local temp_file resource_id
       eval "$state"
       rm -f "$temp_file"
       echo "Cleaned up resource: $resource_id"
   }

   # State is assigned to the variable, no stdout capture needed
   local my_state
   init_function -S my_state
   # Your main script logic here
   cleanup "$my_state"

For backward compatibility, the old stdout capture method still works:

.. code-block:: bash

   # Capture the opaque state snippet emitted on stdout
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

hs_persist_state_as_code
~~~~~~~~~~~~~~~~

Emits Bash code that restores specified local variables in a receiving scope.
The emitted snippet only assigns values if the target variable is declared
`local` in the receiving scope and is still empty.

The function accepts optional `-s` or `-S` arguments:

- `-s <state>`: Treats `<state>` as an existing state snippet to append to.
- `-S <var>`: Assigns the state (appended to any existing content in `<var>`) to the variable named `<var>` instead of printing to stdout.

These options can be used together; when both are provided, `<var>` is used for output and must be empty or uninitialized.

This allows avoiding stdout output for opaque data when assigning to a variable,
while maintaining backward compatibility for appending to state strings or state vars.

.. warning::
   When using `-S` with a variable name, the function will `eval` the current contents of that variable during collision checking. Callers must ensure the variable contains only safe, trusted Bash code or is empty/unset to avoid execution of harmful code.
   

Code protections ensure that prior state is only evaluated when necessary for collision 
checking, and only if the variable is not empty. Corrupted state code is detected when
it calls undefined commands during this evaluation, and when the evaluation takes more
than one second (to prevent hangs).

Libraries are encouraged to provide the same ``-s`` and ``-S`` options to their initialization
functions to allow callers to chain state snippets together.

When appending to an existing state snippet, the function checks for name collisions
and refuses to overwrite existing variables. Some library combinations can be 
incompatible with the chaining approach because they use overlapping variable names.
The alternate solution is to keep and eval separate state snippets for each library.

- Usage: `hs_persist_state_as_code [-s <state> | -S <var>] var1 var2 ...`
- Output: a string of Bash code intended to be `eval`'d by the caller (when not assigning to variable).
- Errors:
  - Refuses to take into account more than one prior state.
  - Detects an invalid variable name passed to option `-S`.
  - Refuses to persist reserved names `__var_name`, `__existing_state`, `__output_state_var` and `__output`.
  - Rejects collisions when a variable already exists in the provided prior state.
  - Detects some the most severe forms of corrupted prior state code (hangs or undefined commands).
- Guarantees:
  - Errors out or succeeds in an atomic manner; no partial state is emitted on error.

.. warning::
  The function cannot currently properly capture arrays, namerefs, associative arrays nor
  functions. Only scalar string variables are supported.

hs_destroy_state
~~~~~~~~~~~~~~~~

Rebuilds a persisted state snippet while removing specific variable
definitions from it. This is intended for cleanup paths that need to strip a
library's own variables from a shared state vector so the same init function
can later be called again without triggering name-collision errors in
``hs_persist_state_as_code``.

The function accepts optional ``-s`` or ``-S`` arguments:

- ``-s <state>``: treats ``<state>`` as the input state snippet and prints the
  rebuilt state to stdout.
- ``-S <var>``: reads the input state from variable ``<var>``, removes the
  listed variables, and writes the rebuilt state back into ``<var>``.

The arguments after the options are the variable names to destroy. Each name
must be a valid shell variable name and must already exist in the input state.

- Usage: ``hs_destroy_state [-s <state> | -S <var>] var1 var2 ...``
- Output: a rebuilt Bash state snippet with the requested variables removed
  (when not assigning to a variable via ``-S``).
- Errors:
  - Detects an invalid variable name passed either to ``-S`` or in the destroy list.
  - Fails if a requested variable is not defined in the input state.
  - Detects corrupt prior state when the input cannot be interpreted as a
    state snippet emitted by ``hs_persist_state_as_code``.
- Guarantees:
  - Rebuilds the resulting state from the surviving variables rather than
    mutating the original text blocks in place.

This is the typical pattern:

.. code-block:: bash

   init_function() {
       local temp_file="/tmp/some_temp_file"
       local resource_id="resource_123"
       hs_persist_state_as_code -S state temp_file resource_id
   }

   cleanup_function() {
       local temp_file resource_id
       eval "$state"
       rm -f "$temp_file"
       hs_destroy_state -S state temp_file resource_id
   }

After ``cleanup_function`` has removed its own variables from ``state``, a
later call to ``init_function`` can reuse the same state variable without
colliding with stale entries from the previous cycle.

hs_read_persisted_state
~~~~~~~~~~~~~~~~~~~~~~~

This function is a simple wrapper around `echo`. `hs_read_persisted_state`
accepts the name of the variable holding the persisted state and reads it via a
nameref. It currently requires eval because the persisted state is stored as a Bash code
snippet. This is a property of the chosen format, not a fundamental limitation
of Bash for restoring values into already-declared caller-local variables.
The output must be `eval`'d by the caller to restore state anyway and the
effect is identical to `eval "$state"`. Code readability is slightly improved
by using this function, and code is future proven against format changes.

- Usage: `eval "$(hs_read_persisted_state state)"`

hs_get_pid_of_subshell
~~~~~~~~~~~~~~~~~~~~~~

Parses the `hs_cleanup_output` function definition to extract the background
reader PID. This is used to detect whether logging setup has already occurred.

Error Codes
-----------

- `HS_ERR_RESERVED_VAR_NAME=1`: a reserved variable name was passed to
  `hs_persist_state_as_code`.
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

`hs_persist_state_as_code` captures caller-local variables by name, embeds their values
in a guarded assignment snippet, and prints that snippet. The guards ensure that
only `local` variables are populated in the receiving scope and that non-empty
locals are not overwritten.

State Destruction
~~~~~~~~~~~~~~~~~

`hs_destroy_state` scans a persisted state snippet for the variable headers
emitted by `hs_persist_state_as_code`, computes the survivor list, then rebuilds the
state from those survivors. This keeps the removal logic centralized in
`handle_state.sh` and gives libraries a way to reuse a shared state variable
across several init/cleanup cycles.

Supported Variables
-------------------

`hs_persist_state_as_code` reliably preserves local scalar variables (strings or numbers)
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
  hs_persist_state_as_code encoded
  # In the cleanup function
  local state="$1"
  local encoded
  eval "$(hs_read_persisted_state state)"
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
