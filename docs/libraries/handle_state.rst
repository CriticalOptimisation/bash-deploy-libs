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
       hs_persist_state "$@" -- temp_file resource_id || return $?
   }

   cleanup_function() {
       local temp_file resource_id
       eval "$(hs_read_persisted_state "$@")" || return $?
       rm -f "$temp_file"
       printf 'Cleaned up resource: %s\n' "$resource_id"
       hs_destroy_state "$@" -- temp_file resource_id || return $?
   }

   local state_var=""
   init_function -S state_var || return $?
   cleanup_function -S state_var || return $?

Public API
----------

hs_persist_state
~~~~~~~~~~~~~~~~

``hs_persist_state`` appends the current values of selected local
variables to the opaque state object named by ``-S``.

- Usage: ``hs_persist_state [forwarded args] -S <statevar> [--] var1 var2 ...``
- Preferred usage: ``hs_persist_state "$@" -- var1 var2 ...``
- State transport is by name only. Stdout is not part of this API.
- If ``--`` is present, its last occurrence starts the explicit variable list.
- Without ``--``, the trailing valid Bash identifiers are treated as the
  variable list.
- Unknown forwarded options before the effective separator are ignored by this
  helper so wrappers can pass ``"$@"`` directly.

Behavior:

- Requested variables that are unset are skipped silently.
- Scalars, indexed arrays, and associative arrays are all persisted natively.
- Namerefs are persisted only when their target variable is also being
  persisted in the same call or already present in the prior state. Nameref
  records are always stored after their targets so restoration order is valid.
- Function names and undeclared names are errors.
- If the destination state already contains variables with the same names, the
  function fails before writing anything.

Errors:

- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  requested variable name.
- ``HS_ERR_RESERVED_VAR_NAME=1``: requested name collides with an internal
  helper variable name.
- ``HS_ERR_VAR_NAME_COLLISION=2``: one or more requested names already exist in
  the prior state.
- ``HS_ERR_CORRUPT_STATE=4``: the prior state is not a valid HS2 object.
- ``HS_ERR_UNKNOWN_VAR_NAME=10``: a requested variable name is not declared
  in the caller's scope, or is a function name.
- ``HS_ERR_NAMEREF_TARGET_NOT_PERSISTED=12``: a nameref's target variable is
  not being persisted in the same call and is not already in the prior state.

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
  checks in ``hs_persist_state``.

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

Restore form selection
^^^^^^^^^^^^^^^^^^^^^^

Two restore forms are available. Choose based on where the target variables live:

- **Implicit form** (preferred for the common case): no ``--`` and no variable
  names are passed. The function emits a snippet that the caller ``eval``\s.
  Because the snippet runs ``local -p`` directly in the caller's scope, it can
  only target variables that are declared local *and* unset in the immediate
  caller. This form is provably free of global scope pollution.

  .. code-block:: bash

     cleanup_function() {
         local temp_file resource_id
         eval "$(hs_read_persisted_state "$@")" || return $?
         rm -f "$temp_file"
         printf 'Cleaned up resource: %s\n' "$resource_id"
     }

- **Explicit form**: variable names are supplied after ``--``. The function
  restores each name by traversing the full dynamic scope (caller chain and
  globals). Use this form when targeting a variable declared in a higher-level
  caller, or an explicitly declared but unset global. It is also appropriate
  when only a named subset of the state is needed.

  .. code-block:: bash

     cleanup_function() {
         local temp_file resource_id
         hs_read_persisted_state "$@" -- temp_file resource_id || return $?
         rm -f "$temp_file"
         printf 'Cleaned up resource: %s\n' "$resource_id"
     }

Explicit restore
^^^^^^^^^^^^^^^^

Behavior:

- Each requested name is looked up by traversing the full dynamic scope.
- A name not declared anywhere in the dynamic scope is an error.
- A name that is set (including an empty-string value) is an error; ``unset``
  the variable explicitly before calling if an overwrite is intended.
- Requested names missing from the state object are warnings, one per variable.
- ``-q`` suppresses those warnings.
- Scalars, indexed arrays, and associative arrays are all restored natively.
- Namerefs cannot be restored via the explicit form; use the eval/stdout form
  instead (see nameref example in the Examples section).

Implicit local restore
^^^^^^^^^^^^^^^^^^^^^^

When no explicit variable names are supplied and no explicit ``--`` is present,
``hs_read_persisted_state`` emits a small safe, locally generated implicit
restore snippet. The caller must ``eval`` the snippet using the
forwarded-arguments form:

.. code-block:: bash

   cleanup_function() {
       local temp_file resource_id
       eval "$(hs_read_persisted_state "$@")" || return $?
       rm -f "$temp_file"
       printf 'Cleaned up resource: %s\n' "$resource_id"
   }

The generated snippet:

- scans ``local -p`` in the immediate caller scope,
- keeps only unset scalar locals,
- ignores locals whose names start with ``__hs_``,
- reenters ``hs_read_persisted_state -q -S <statevar> -- ...``,
- redirects that reentrant call's stdout to ``/dev/null``.

The emitted snippet is safe: the only elements derived from the transmitted
state are valid Bash identifiers that are tested for existence as local
variables in the caller's scope. The caller evaluates safe probing code, not
the persisted state transmitted by the caller directly.

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
- ``HS_ERR_UNKNOWN_VAR_NAME=10``: a requested variable name (explicit form) is
  not declared anywhere in the dynamic scope.
- ``HS_ERR_VAR_ALREADY_SET=11``: a requested variable name (explicit form) is
  set (including empty string); ``unset`` the variable first if an overwrite
  is intended.

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
- ``HS_ERR_UNKNOWN_VAR_NAME=10``
- ``HS_ERR_VAR_ALREADY_SET=11``
- ``HS_ERR_NAMEREF_TARGET_NOT_PERSISTED=12``

Known Limitations
-----------------

- Namerefs cannot be restored via the explicit restore form of
  ``hs_read_persisted_state``; use the eval/stdout form
  (``eval "$(hs_read_persisted_state "$@")"``).
- The HS2 cksum detects accidental corruption but does not authenticate the
  state against intentional tampering; treat the state variable as trusted
  within the process.

Examples
--------

Persisting and restoring a scalar:

.. code-block:: bash

   init_function() {
       local token='a b "c" $d'
       hs_persist_state "$@" -- token || return $?
   }

   cleanup_function() {
       local token
       hs_read_persisted_state "$@" -- token || return $?
       printf '%s\n' "$token"
   }

.. code-block:: bash

   local state_var=""
   init_function -S state_var || return $?
   cleanup_function -S state_var || return $?

Persisting and restoring an indexed array:

.. code-block:: bash

   init_function() {
       local -a items=("value1" "value2" "value with spaces")
       hs_persist_state "$@" -- items || return $?
   }

   cleanup_function() {
       local -a items
       hs_read_persisted_state "$@" -- items || return $?
       printf '%s\n' "${items[@]}"
   }

.. code-block:: bash

   local state_var=""
   init_function -S state_var || return $?
   cleanup_function -S state_var || return $?

Persisting a nameref alongside its target (active-character pattern):

.. code-block:: bash

   init_function() {
       local -A commander=([hp]=100 [name]="Shepard")
       local -A wrex=([hp]=200 [name]="Wrex")
       local -n active=commander
       hs_persist_state "$@" -- commander wrex active || return $?
   }

   cleanup_function() {
       local -A commander wrex
       local -n active
       eval "$(hs_read_persisted_state "$@")" || return $?
       printf 'Active: %s (HP: %s)\n' "${active[name]}" "${active[hp]}"
   }

.. code-block:: bash

   local state_var=""
   init_function -S state_var || return $?
   cleanup_function -S state_var || return $?

Caveats
-------

- Prefer the implicit restore form (``eval "$(hs_read_persisted_state "$@")"``
  ``|| return $?``) for cleanup functions that restore into their own locals.
  Use the explicit form only when targeting variables in a higher-level caller,
  declared globals, or a named subset of the state.
- The state format (HS2) is a structured data format, not executable code.
  Calling ``eval "$state_var"`` directly will fail; always restore via
  ``hs_read_persisted_state``.
- The state variable is opaque: do not inspect, modify, or concatenate its
  value outside the public API.
- ``eval`` is used per-record internally (on ``declare`` statements only);
  the state is never evaluated as an arbitrary code block.

Source Listing
--------------

.. literalinclude:: ../../config/handle_state.sh
   :language: bash
   :linenos:
