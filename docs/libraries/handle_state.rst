Handle State Library
====================

Location
--------

- `config/handle_state.sh`

Purpose
-------

This library provides two core capabilities for Bash libraries:

- Persisting local variable state from one function to another (typically
  initialization to cleanup) via a generated snippet stored in a named state variable.
- Providing a logging FIFO and background reader process for cases where
  subshell output still needs to be surfaced in the main script output.

Dependencies
------------

This library depends on the Command Guard Library (`config/command_guard.sh`)
for secure execution of external commands. The dependency is automatically
resolved when the library is sourced.

Quick Start
-----------

Source the file once, then use `hs_persist_state_as_code` in the init function and
`hs_read_persisted_state` in cleanup.

.. code-block:: bash

   # Source once in the main script of your library
   source "$(dirname "$0")/config/handle_state.sh"

   init_function() {
       # Direct output to stdout would mess up the state snippet, so use hs_echo if needed
       hs_echo "Initializing..."
       # Define some opaque library resources
       local temp_file="/tmp/some_temp_file"
       local resource_id="resource_123"
       hs_persist_state_as_code -S state temp_file resource_id
   }

   cleanup() {
       local state_var="$1"
       local temp_file resource_id
       hs_read_persisted_state "$state_var" temp_file resource_id
       rm -f "$temp_file"
       echo "Cleaned up resource: $resource_id"
   }

   # State is assigned to the variable, no stdout capture needed
   local my_state
   init_function -S my_state
   # Your main script logic here
   cleanup "$my_state"

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

The function requires the `-S` argument:

- `-S <var>`: Assigns the state (appended to any existing content in `<var>`) to the variable named `<var>`.

.. warning::
   When using `-S` with a variable name, the function will `eval` the current contents of that variable during collision checking. Callers must ensure the variable contains only safe, trusted Bash code or is empty/unset to avoid execution of harmful code.
   

Code protections ensure that prior state is only evaluated when necessary for collision 
checking, and only if the variable is not empty. Corrupted state code is detected when
it calls undefined commands during this evaluation, and when the evaluation takes more
than one second (to prevent hangs).

Libraries are encouraged to provide the same ``-S`` option to their initialization
functions so callers can keep state transport explicit and by-name.

When appending to an existing state snippet, the function checks for name collisions
and refuses to overwrite existing variables. Some library combinations can be
incompatible with the chaining approach because they use overlapping variable names.
The alternate solution is to keep separate state variables for each library.

- Usage: `hs_persist_state_as_code -S <var> var1 var2 ...`
- Output: writes a string of Bash code intended to be `eval`'d by the caller into `<var>`.
- Errors:
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

The function requires the ``-S`` argument:

- ``-S <var>``: reads the input state from variable ``<var>``, removes the
  listed variables, and writes the rebuilt state back into ``<var>``.

The arguments after the options are the variable names to destroy. Each name
must be a valid shell variable name and must already exist in the input state.

- Usage: ``hs_destroy_state -S <var> var1 var2 ...``
- Output: rewrites ``<var>`` with a rebuilt Bash state snippet with the requested variables removed.
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

`hs_read_persisted_state` reads state from a named state variable. It supports
two modes:

- Explicit restore: ``hs_read_persisted_state state foo bar``
- Probe-snippet generation: ``eval "$(hs_read_persisted_state state)"``

Explicit restore is the preferred API. The caller names exactly which variables
must be restored, and `hs_read_persisted_state` writes those values into the
current caller scope.

When no explicit variable list is given, `hs_read_persisted_state` does not
return the raw persisted state snippet. Instead, it emits a locally generated
probe snippet. When that snippet is `eval`'d, it checks the immediate caller
scope for matching ``local`` variables that are currently empty, then reenters
`hs_read_persisted_state` with that explicit list.

This design is safer than `eval "$state"` because the caller executes only the
local probe snippet, not the transmitted persisted state directly. Direct
``eval`` of the raw state is discouraged outside early unit tests of the library.

.. warning::

   Without an explicit variable list, every empty ``local`` variable in the
   immediate caller scope whose name also exists in the state may be restored
   automatically. This may be unwanted if the caller manages several unrelated
   state variables or reuses the same local names for different purposes.
   Prefer explicit variable lists in non-trivial cleanup functions.

Automatic probing only inspects the immediate caller scope. Locals declared in
the caller's caller are not restored automatically, but they can still be
restored if an intermediate function knows their name and names them explicitly.

The optional ``-q`` flag suppresses warnings for explicitly requested variables
that are not present in the state. It is intended for explicit
caller-supplied variable lists. When probing automatically, only variables 
present in the state are probed.

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

State Restoration
~~~~~~~~~~~~~~~~~

`hs_read_persisted_state` should usually be used in one of these forms:

- ``hs_read_persisted_state state foo bar``
- ``eval "$(hs_read_persisted_state state)"``

The first form is preferred because it is explicit and does not require the
caller to execute the transmitted state snippet. The second form exists for the
common case where the caller simply wants all matching empty locals in its own
scope restored.

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
  hs_persist_state_as_code -S state encoded
  # In the cleanup function
  local state_var="$1"
  local encoded
  hs_read_persisted_state "$state_var" encoded
  declare -a newarray
  mapfile -d '' -t newarray < <(printf '%s' "$encoded" | base64 -d)
Caveats
-------

- Prefer ``hs_read_persisted_state state var1 var2`` over direct ``eval``.
- If you use ``eval "$(hs_read_persisted_state state)"``, declare target
  variables ``local`` first and remember that only the immediate caller scope
  is probed automatically.
- Direct ``eval "$state"`` should be avoided in library code unless you are
  deliberately handling the raw persisted snippet yourself.
- The library uses `eval` internally; treat state strings as trusted input.
- Call `hs_cleanup_output` when you are done to stop the background reader.

Source Listing
--------------

.. literalinclude:: ../../config/handle_state.sh
   :language: bash
   :linenos:
