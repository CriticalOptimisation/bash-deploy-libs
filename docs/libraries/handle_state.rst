Handle State Library
====================

Location
--------

- ``config/handle_state.sh``

Purpose
-------

``handle_state.sh`` helps Bash libraries carry private global state information 
between functions, without polluting the global namespace. It also allows applications
to carry several distinct states, one for each context.

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

The library depends on the ``command_guard.sh`` library and fails at load time if
it cannot load its dependency.

Errors:

- ``HS_ERR_DEPENDENCY_MISSING=19``: The library failed to load due to a missing dependency.


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
- ``--list-reserved``: prints one reserved internal variable name per line to
  stdout and returns 0. Incompatible with all other options. Intended for
  testing only. All three entry points produce identical output; this form is
  the canonical one.

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
- ``HS_ERR_MULTIPLE_STATE_INPUTS=3``: ``-S`` was given more than once; repeating
  the option is not allowed even when both occurrences name the same variable.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  requested variable name.
- ``HS_ERR_RESERVED_VAR_NAME=1``: requested name starts with the reserved
  prefix ``__hs_``. Run ``hs_persist_state --list-reserved`` for the current
  list of prohibited names.
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
- ``--list-reserved``: prints reserved internal variable names to stdout and
  returns 0. Incompatible with all other options. Intended for testing only.
  See ``hs_persist_state --list-reserved`` for the authoritative list.

Behavior:

- Every requested destroy variable must already exist in the input state.
- The output state is rebuilt from the surviving variables instead of editing
  the original text in place.
- After cleanup has destroyed a library's own entries, the same named state
  variable can be reused by a later init call without tripping the collision
  checks in ``hs_persist_state``.

Errors:

- ``HS_ERR_STATE_VAR_UNINITIALIZED=7``: missing ``-S <statevar>``.
- ``HS_ERR_MULTIPLE_STATE_INPUTS=3``: ``-S`` was given more than once; repeating
  the option is not allowed even when both occurrences name the same variable.
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
- ``--list-reserved``: prints reserved internal variable names to stdout and
  returns 0. Incompatible with all other options. Intended for testing only.
  See ``hs_persist_state --list-reserved`` for the authoritative list.

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
- Validation is **all-or-nothing**: all guard conditions (declared, unset) are
  checked for every requested name before any restoration occurs. If any check
  fails, no variable is restored.
- Requested names missing from the state object are warnings, one per variable.
- ``-q`` suppresses those warnings.
- Scalars, indexed arrays, associative arrays, and namerefs are all restored
  natively.

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
   if they are named explicitly.

If ``--`` is present and no variable names follow it, the function emits no
implicit restore snippet and returns success.

Errors:

- ``HS_ERR_MISSING_ARGUMENT=8``: no state variable name was supplied at all.
- ``HS_ERR_MULTIPLE_STATE_INPUTS=3``: ``-S`` was given more than once; repeating
  the option is not allowed even when both occurrences name the same variable.
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

hs_extract_token
~~~~~~~~~~~~~~~~

``hs_extract_token`` has two call forms.

**Direct query form** — ``$1`` is ``--list-reserved``:

.. code-block:: bash

   hs_extract_token --list-reserved

Prints the names forming the collision surface of ``hs_extract_token`` itself,
one per line.  These are the minimum set of names to avoid when naming a ``-S``
state variable; write-capable or ill-designed entry points may add further
prohibited names.  The list is derived dynamically from ``local -p`` so that
future edits to this function are automatically reflected.

As of the current release the output is:

.. code-block:: text

   __hs_processed
   __hs_remaining

When used in a read-write entry-point pattern, calling the entry point with
``--list-reserved`` prints the merged collision surface, which includes
``hs_extract_token``'s own names plus the source-local name (``$2``).  For
``__wt_tok`` as the source local, the output is:

.. code-block:: text

   __hs_processed
   __hs_remaining
   __wt_tok

.. note::

   The reserved-name list is part of the minor API: its prefix conventions will
   not change across minor versions, but individual names may be added or
   removed.  Code that avoids the entire ``__hs_`` namespace is unaffected by
   such changes; code that checks for specific names may break on a minor
   update.

**Eval form** — ``$1`` is the calling function name, ``$2`` is the local name, ``${@:3}`` are the forwarded args:

.. code-block:: bash

   eval "$(hs_extract_token mylib_func __mod_state_token "$@")" || return $?

The eval form has two operational modes selected automatically by the caller's
argument list:

*Normal mode* (``$3`` is not ``--list-reserved``): parses ``-S <statevar>``
from ``${@:3}`` and emits ``local __mod_state_token='<token_value>'`` on
success or ``bash -c 'exit N'`` on error.  Runs in a ``$(...)`` subshell; the
collision surface at fork time consists of ``hs_extract_token``'s own
locals.  ``-S`` is **mandatory**: omitting it is a structural error
(``HS_ERR_STATE_VAR_UNINITIALIZED``, printed to stderr).

*List-reserved mode* (``$3 == --list-reserved``): activated when the caller
passes ``--list-reserved`` as their first argument (so ``${@:3}`` of
``hs_extract_token`` is exactly ``--list-reserved``).  Instead of extracting a
state value, it emits eval-code that declares the token local and assigns it a
**mode token** — a real HS2 object whose checksum field is replaced by a
non-numeric marker only ``hs_extract_token`` can emit:

.. code-block:: text

   HS2:mode=list-reserved:declare -a reserved_names=([0]="__hs_processed" [1]="__hs_remaining" ...)

The payload (a ``reserved_names`` array) is built with ``hs_persist_state`` and
carries the merged collision surface: ``hs_extract_token``'s own names **plus a
capture of the entry-point frame** taken at eval time (so locals the entry
point declared *before* the eval are included).  The token local (``$2``) is
declared **last, immediately before assignment**, so it never appears in its
own capture; whether ``$2`` belongs in the reported surface is decided later by
``hs_finalize_token`` (see below), not here.  No further arguments are valid in
this mode.

Because the marker replaces the numeric checksum, a normal token can never
equal a mode token: every non-token-utility consumer rejects it with the
discriminable ``HS_ERR_LIST_RESERVED_TOKEN`` (see `Error Codes`_), and
``hs_is_list_reserved_mode`` / ``hs_finalize_token`` recognise it structurally.

Errors: same set as the shared option parser; ``-S`` is mandatory in normal
mode.

hs_finalize_token
~~~~~~~~~~~~~~~~~

``hs_finalize_token`` terminates every entry point.  It is **always** called
(replacing the former ``hs_write_token``), and its behaviour is driven entirely
by the token it is handed — never by re-sniffing ``$@``.

- Usage: ``eval "$(hs_finalize_token <API_function> <token_local> "$@")"``.
- ``$1`` is the calling API function name (used in error messages).
- ``$2`` is the name of the local holding the token (accessed by position).
- Runs in a ``$(...)`` subshell, inheriting the calling frame read-only for the
  write path; the list-reserved report path emits code that runs in the
  entry-point frame so it can capture that frame afresh.

Behaviour, selected by the token's checksum field:

- **Mode token** (field starts with ``mode=``): emit the collision-surface
  report — read ``reserved_names`` back out of the token, merge it with
  ``hs_finalize_token``'s own surface **and a fresh capture of the entry-point
  frame** (catching locals declared between the two evals), then print one name
  per line and ``return 0``.  The token local ``$2`` is **included** unless the
  marker ends in ``-ro`` (read-only; see ``hs_read_only``), in which case it is
  excluded.  The reported conflicting token name is always ``$2`` — the fixed
  internal state-token name — independent of any external ``-S`` name.
- **Normal token** (numeric checksum) with ``-S <statevar>`` present: emit
  ``<statevar>='<token_value>'`` — a plain assignment writing the (possibly
  updated) token back.  Idempotent when the body left the token unchanged.
- **Normal token** with no ``-S``: emit nothing and ``return 0`` — the entry
  point is read-only with respect to external state.
- On error: prints ``bash -c 'exit N'``.

See `Entry-Point Pattern`_ for canonical usage examples.

hs_is_list_reserved_mode
~~~~~~~~~~~~~~~~~~~~~~~~~

``hs_is_list_reserved_mode -S <token_local>`` returns 0 iff the named token is a
list-reserved mode token (checksum field starts with ``mode=list-reserved``,
matching both the read-write baseline and the ``-ro`` variant), non-zero
otherwise.  It reads the token through dynamic scope and never accesses external
state, so it carries no collision surface of its own.  It is the body-skip guard
in the canonical skeleton: the entry-point body runs only when the token is a
real state token.

hs_read_only
~~~~~~~~~~~~

``hs_read_only <API_function> <token_local> "$@"`` marks an entry point as
read-only with respect to external state.  It is an **optional** line in the
canonical skeleton; include it only in entry points that never write state back.
Its single, mode-agnostic rule inspects the token's checksum field:

- **numeric checksum** (a normal state token, or an empty / non-HS2 token):
  strip ``-S <var>`` from ``$@`` (emit ``set -- …``) so ``hs_finalize_token``
  performs no write-back.
- **``mode=…`` marker** (any mode): append ``-ro`` to the marker
  (idempotently — never a double ``-ro``), leaving the payload untouched, so
  ``hs_finalize_token`` excludes the token local ``$2`` from the reported
  surface.

Because the rule keys only on the ``mode=`` prefix, every present and future
mode gains a read-only variant (``mode=X`` → ``mode=X-ro``) for free.

Entry-Point Pattern
~~~~~~~~~~~~~~~~~~~

Libraries that expose ``-S <statevar>`` and use ``handle_state.sh`` internally
should structure **every** stateful entry point with the same three-line
skeleton, regardless of whether it reads, writes, or both:

.. code-block:: bash

   mylib_func() {
       eval "$(hs_extract_token  mylib_func __mylib_state_token "$@")" || return $?
       # eval "$(hs_read_only    mylib_func __mylib_state_token "$@")" || return $?   # <-- uncomment iff this entry point never writes state back
       hs_is_list_reserved_mode -S __mylib_state_token || { _mylib_func "$@" || return $?; }
       eval "$(hs_finalize_token mylib_func __mylib_state_token "$@")" || return $?
   }

The three steps are always *extract → body-unless-listing → finalize*:

#. ``hs_extract_token`` populates the token local — either the caller's state
   (normal mode) or a mode token (``--list-reserved``).
#. ``hs_is_list_reserved_mode`` skips the body helper whenever the token is a
   mode token, so no business logic runs during a ``--list-reserved`` query
   (any read or persist attempted there would hit the mode token and fail with
   ``HS_ERR_LIST_RESERVED_TOKEN``).
#. ``hs_finalize_token`` writes the token back (normal mode) or emits the
   collision report (list-reserved mode).

**Read-write** and **read/modify/write** entry points use the skeleton as shown.
The body helper reads from and persists to the token local via dynamic scoping:

.. code-block:: bash

   _mylib_func() {
       local var1 var2
       eval "$(hs_read_persisted_state -S __mylib_state_token)" || return $?   # implicit form preferred
       # ... mutate var1, var2 as needed ...
       # Destroy before re-persisting to avoid HS_ERR_VAR_NAME_COLLISION.
       hs_destroy_state -S __mylib_state_token -- var1 var2 || return $?
       hs_persist_state -S __mylib_state_token -- var1 var2 || return $?
   }

**Read-only** entry points uncomment the ``hs_read_only`` line.  In normal mode
it strips ``-S`` so ``hs_finalize_token`` performs no write-back; in
list-reserved mode it appends ``-ro`` to the token marker so the report excludes
the token local.  The body helper simply omits the destroy/persist calls:

.. code-block:: bash

   _mylib_ro_func() {
       local var1 var2
       eval "$(hs_read_persisted_state -S __mylib_state_token)" || return $?   # implicit form preferred
       # ... read-only work ...
   }

Whether a call ultimately modifies the state is a **runtime** property of the
body — the finalizer simply serialises whatever the token holds — so a helper
that conditionally mutates state needs no special flag and no branch in the
entry point.

.. warning::

   ``hs_destroy_state`` modifies the token **in the caller's variable**
   immediately.  If ``hs_persist_state`` subsequently fails, the destroyed
   variables are lost from the token.  Always call both functions in the
   same body helper so that any error causes the whole entry point to abort
   via ``return $?`` before ``hs_finalize_token`` propagates an incomplete
   token back to the caller.  Bash's sequential execution model and the
   fact that subshells cannot write back to the parent shell's variables
   make this pattern safe under normal control flow: there is no concurrent
   access that could observe a partially-updated token.

.. note::

   Subshells (``$(...)`` command substitutions and explicit ``( )``
   subshell groups) inherit a **copy** of the parent shell's environment.
   Any variable assignment or ``hs_persist_state`` call inside a subshell
   affects only that copy; the parent's token variable is never updated.
   This means ``handle_state.sh`` state can only be advanced by code that
   runs directly in the relevant shell process.  Functions that run in a
   subshell (e.g. to capture their output) cannot update the caller's token
   even if they call ``hs_persist_state`` successfully.

The ``--list-reserved`` output differs by entry-point type, because
``hs_finalize_token`` includes the token local only when the mode marker lacks
the ``-ro`` suffix:

- **Read-write / read-modify-write** (no ``hs_read_only``; marker
  ``mode=list-reserved``): prints ``__hs_processed``, ``__hs_remaining``, and
  ``__mylib_state_token``.
- **Read-only** (``hs_read_only`` uncommented; marker ``mode=list-reserved-ro``):
  prints only ``__hs_processed`` and ``__hs_remaining`` — the token local is
  excluded because no write-back can shadow the caller's ``-S`` name.

Developer Reference
-------------------

.. warning::

   The functions documented in this section are internal implementation details.
   They are not part of the public API and may change signature or be removed
   without notice. Application and library code must not call them directly.

_hs_resolve_state_inputs
~~~~~~~~~~~~~~~~~~~~~~~~

``_hs_resolve_state_inputs`` is the shared option parser used by the public
entry points.

The caller must declare the following variables before calling this helper:

.. code-block:: bash

   local -a __hs_remaining=()
   local -A __hs_processed=()

The helper writes its output into those exact names through Bash dynamic
scoping. On success, ``__hs_processed`` may contain:

- ``state``: validated state variable name from ``-S``
- ``quiet``: ``true`` or ``false``
- ``vars``: explicit variable-name list, serialized as a space-separated string
- ``separator``: present when an explicit ``--`` was seen

Errors:

- ``HS_ERR_MISSING_ARGUMENT=8``: required option parameter missing.
- ``HS_ERR_INVALID_VAR_NAME=5``: invalid state variable name or invalid
  explicit variable-name token.
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
- ``HS_ERR_LIST_RESERVED_TOKEN=13``: a list-reserved **mode token** (checksum
  field starting with ``mode=``) was handed to a normal state consumer
  (``hs_persist_state``, ``hs_destroy_state``, ``hs_read_persisted_state``).
  A mode token carries only the reserved-name surface and is not usable as
  state; this code is distinct from ``HS_ERR_CORRUPT_STATE`` so callers can tell
  the two apart.  It signals programmer misuse and is printed to stderr.

Known Limitations
-----------------

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
       eval "$(hs_read_persisted_state "$@")" || return $?   # implicit form preferred
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
- State records are separated internally by ``$'\001'`` and parsed with
  ``IFS=$'\001' read -ra``; the state string is never passed to ``eval``.

Source Listing
--------------

.. literalinclude:: ../../config/handle_state.sh
   :language: bash
   :linenos:

Change History
--------------

.. list-table::
   :header-rows: 1
   :widths: 10 90

   * - PR
     - Summary
   * - #23
     - feature/skills update
   * - #32
     - batch security fixes [closes #7]
   * - #38
     - do not return state via stdout
   * - #63
     - refactor safer handle-state restoration flow [closes #62]
   * - #83
     - fix hs_destroy_state rebuild subprocess helper [closes #82]
   * - #90
     - remove internal-format mention, convenience form non-preferred
   * - #91
     - add forwarded-args eval example for probe-snippet mode
   * - #93
     - rename probe-snippet to implicit local restore [closes #76]
   * - #94
     - emphasize implicit restore snippet is safe local code
   * - #95
     - clarify caller evaluates probe code, not transmitted state
   * - #96
     - add -S calling context to Examples section [closes #80]
   * - #98
     - remove caveat implying raw eval of state is valid [closes #81]
   * - #140
     - add hs_extract_token and hs_write_token; entry-point pattern (issue #136)
   * - #140
     - fix --list-reserved merge for read-write entry points
   * - #145
     - token-borne --list-reserved mode; hs_finalize_token, hs_is_list_reserved_mode, hs_read_only (issue #143)
   * - #145
     - usage on structural call errors; hs_read_only skeleton line gains ``|| return $?`` (issue #146)
   * - #99
     - error on undeclared variable names [closes #1]
   * - #102
     - guard nameref restore against undeclared variables [closes #100]
   * - #103
     - reject function names with HS_ERR_UNKNOWN_VAR_NAME
   * - #105
     - fix hs_persist_state dropping indexed array elements [closes #3]
   * - #109
     - reduce nameref collision surface [closes #104]
   * - #110
     - document HS_ERR_MULTIPLE_STATE_INPUTS for all entry points
