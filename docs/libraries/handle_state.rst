Handle State Library
====================

Location
--------

- ``config/handle_state.sh``

Purpose
-------

``handle_state.sh`` helps Bash libraries carry cleanup state by name.

The public API is built around a named state variable passed with
``-S <statevar>``. The state value is an opaque internal token; callers should
not inspect or modify its contents directly.

Dependencies
------------

This library depends on the Command Guard Library
(``config/command_guard.sh``). The dependency is resolved automatically when
``handle_state.sh`` is sourced.

Quick Start
-----------

.. code-block:: bash

   source "$(dirname "$0")/config/handle_state.sh"

   init_function() {
       local temp_file="/tmp/some_temp_file"
       local resource_id="resource_123"
       hs_persist_state_as_code "$@" -- temp_file resource_id
   }

   cleanup_function() {
       local temp_file resource_id
       hs_read_persisted_state "$@" -- temp_file resource_id
       rm -f "$temp_file"
       printf 'Cleaned up resource: %s\n' "$resource_id"
       hs_destroy_state "$@" -- temp_file resource_id
   }

   local state_var=""
   init_function -S state_var
   cleanup_function -S state_var

Public API
----------

hs_persist_state_as_code
~~~~~~~~~~~~~~~~~~~~~~~~

``hs_persist_state_as_code`` appends the current values of selected local
variables to the opaque state object named by ``-S``.

- Usage: ``hs_persist_state_as_code [forwarded args] -S <statevar> [--] var1 var2 ...``
- Preferred usage: ``hs_persist_state_as_code "$@" -- var1 var2 ...``
- State transport is by name only. Stdout is not part of this API.
- If ``--`` is present, its last occurrence starts the explicit variable list.
- Without ``--``, the trailing valid Bash identifiers are treated as the
  variable list.
- Unknown forwarded options before the effective separator are ignored by this
  helper so wrappers can pass ``"$@"`` directly.

Behavior:

- Requested variables that are unset are skipped.
- Unknown names and function names are ignored.
- Indexed arrays currently persist only their first element.
- Associative arrays are ignored.
- Namerefs are persisted as scalar values.
- If the destination state already contains persisted variables with the same
  names, the function fails before writing anything.

Errors:

- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  requested variable name.
- ``HS_ERR_RESERVED_VAR_NAME=1``: requested name collides with an internal
  helper variable name.
- ``HS_ERR_VAR_NAME_COLLISION=2``: one or more requested names already exist in
  the prior state.
- ``HS_ERR_CORRUPT_STATE=4``: the prior state could not be evaluated safely
  during collision checking.

hs_destroy_state
~~~~~~~~~~~~~~~~

``hs_destroy_state`` removes selected variable names from an existing opaque
state object and writes the rebuilt state back to the same named variable.

- Usage: ``hs_destroy_state [forwarded args] -S <statevar> [--] var1 var2 ...``
- Preferred usage: ``hs_destroy_state "$@" -- var1 var2 ...``
- If ``--`` is present, its last occurrence starts the explicit destroy list.
- Without ``--``, the trailing valid Bash identifiers are treated as the
  destroy list.

Behavior:

- Every requested destroy variable must already exist in the input state.
- The output state is rebuilt from the surviving variables instead of editing
  the original text in place.
- After cleanup has destroyed a library's own entries, the same named state
  variable can be reused by a later init call without tripping the collision
  checks in ``hs_persist_state_as_code``.

Errors:

- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  requested destroy name.
- ``HS_ERR_VAR_NAME_NOT_IN_STATE=6``: requested destroy name is not present in
  the input state.
- ``HS_ERR_CORRUPT_STATE=4``: the input state cannot be parsed or rebuilt
  safely.

hs_read_persisted_state
~~~~~~~~~~~~~~~~~~~~~~~

``hs_read_persisted_state`` restores values from a named opaque state object.

- Usage: ``hs_read_persisted_state [forwarded args] [-q] -S <statevar> [--] [var1 var2 ...]``
- Convenience form: ``hs_read_persisted_state state_var ...`` is normalized to
  ``-S state_var ...``. Not recommended in library code; prefer explicit ``-S``.
- Preferred usage: ``hs_read_persisted_state "$@" -- var1 var2 ...``

Explicit restore
^^^^^^^^^^^^^^^^

When variable names are supplied, the function restores only those names into
the current caller scope.

.. code-block:: bash

   cleanup_function() {
       local temp_file resource_id
       hs_read_persisted_state "$@" -- temp_file resource_id
   }

Behavior:

- Restoration is by name into already-declared locals in the caller scope.
- Requested names missing from the state are warnings, one per variable.
- ``-q`` suppresses those warnings.
- The current implementation restores scalar string values only.

Implicit local restore
^^^^^^^^^^^^^^^^^^^^^^

When no explicit variable names are supplied and no explicit ``--`` is present,
``hs_read_persisted_state`` emits a small locally generated implicit restore snippet. The
caller must ``eval`` the snippet using the forwarded-arguments form:

.. code-block:: bash

   cleanup_function() {
       local temp_file resource_id
       eval "$(hs_read_persisted_state "$@")"
       rm -f "$temp_file"
       printf 'Cleaned up resource: %s\n' "$resource_id"
   }

The generated snippet:

- scans ``local -p`` in the immediate caller scope,
- keeps only unset scalar locals,
- ignores locals whose names start with ``__hs_``,
- reenters ``hs_read_persisted_state -q -S <statevar> -- ...``,
- redirects that reentrant call's stdout to ``/dev/null``.

This is safer than directly evaluating the opaque state object because the
caller only evaluates the locally generated implicit restore code.

.. warning::

   Without an explicit variable list, every unset scalar local in the immediate
   caller scope may be considered for restoration. This can be the wrong
   behavior if the caller manages several unrelated state variables or reuses
   common local names. Prefer explicit variable lists in non-trivial cleanup
   paths rather than relying on implicit local restore.

.. warning::

   Automatic probing only inspects the immediate caller scope. Locals in the
   caller's caller are not restored automatically. They can still be restored
   if an intermediate function names them explicitly.

If ``--`` is present and no variable names follow it, the function emits no
implicit restore snippet and returns success.

Errors:

- ``HS_ERR_MISSING_ARGUMENT=8``: no state variable name was supplied at all.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  requested restore name.
- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``, or the named
  state variable is unset or empty.
- ``HS_ERR_CORRUPT_STATE=4``: the state cannot be evaluated safely while
  restoring explicitly requested variables.

Helper API
----------

_hs_resolve_state_inputs
~~~~~~~~~~~~~~~~~~~~~~~~

``_hs_resolve_state_inputs`` is the shared option parser used by the public
entry points.

- It fills an indexed array of unprocessed forwarded arguments.
- It fills an associative array of processed values:

  - ``state``: validated state variable name from ``-S``
  - ``quiet``: ``true`` or ``false``
  - ``vars``: explicit variable-name list, serialized as a space-separated string
  - ``separator``: present when an explicit ``--`` was seen

Errors:

- ``HS_ERR_MISSING_ARGUMENT=8``: required option parameter missing.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name, invalid
  explicit variable-name token, or a collision where ``$2`` / ``$4`` matches
  one of the helper's own local variable names.
- ``HS_ERR_INVALID_ARGUMENT_TYPE=9``: output containers passed by name are not
  an indexed array and an associative array respectively.
- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``.

Error Codes
-----------

- ``HS_ERR_RESERVED_VAR_NAME=1``
- ``HS_ERR_VAR_NAME_COLLISION=2``
- ``HS_ERR_MULTIPLE_STATE_INPUTS=3``
- ``HS_ERR_CORRUPT_STATE=4``
- ``HS_ERR_INVALID_VAR_NAME=5``
- ``HS_ERR_VAR_NAME_NOT_IN_STATE=6``
- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``
- ``HS_ERR_MISSING_ARGUMENT=8``
- ``HS_ERR_INVALID_ARGUMENT_TYPE=9``

Known Limitations
-----------------

The tests currently demonstrate these limitations:

- unknown variable names passed to ``hs_persist_state_as_code`` are ignored
- function names passed to ``hs_persist_state_as_code`` are ignored
- indexed arrays preserve only their first element
- associative arrays are ignored
- namerefs are restored as scalar values

Examples
--------

Persisting and restoring a scalar:

.. code-block:: bash

   init_function() {
       local token='a b "c" $d'
       hs_persist_state_as_code "$@" -- token
   }

   cleanup_function() {
       local token
       hs_read_persisted_state "$@" -- token
       printf '%s\n' "$token"
   }

Representing an array manually through a scalar encoding:

.. code-block:: bash

   init_function() {
       local -a items=("value1" "value2" "value with spaces")
       local encoded
       encoded=$(printf '%s\0' "${items[@]}" | base64 -w0)
       hs_persist_state_as_code "$@" -- encoded
   }

   cleanup_function() {
       local encoded
       local -a items
       hs_read_persisted_state "$@" -- encoded
       mapfile -d '' -t items < <(printf '%s' "$encoded" | base64 -d)
   }

Caveats
-------

- Prefer explicit restore lists over implicit local restore.
- Do not rely on the opaque state format being executable code forever.
- Early unit tests still use raw ``eval`` against the current code-based state
  representation, but library code should prefer ``hs_read_persisted_state``.
- The current implementation uses ``eval`` internally; state should therefore
  be treated as trusted input.

Source Listing
--------------

.. literalinclude:: ../../config/handle_state.sh
   :language: bash
   :linenos:
