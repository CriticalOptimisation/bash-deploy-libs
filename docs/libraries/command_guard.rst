Command Guard Library
=====================

Location
--------

- `config/command_guard.sh`

Purpose
-------

This library provides a single entry point, ``cg_guard``, that defines a Bash
function named after an external command. The generated function shadows the
external command and dispatches to it by full path, ensuring command resolution
is not affected by untrusted PATH prefixes. A short alias ``guard`` is defined
automatically unless a function named ``guard`` already exists at source time.

Additionally, `cg_safe_run` provides function-scoped PATH restriction: any
unguarded external command invoked inside the called function produces a hard
abort (Bash readonly-assignment failure), making command-injection vulnerabilities
visible at runtime rather than silently exploiting the caller's PATH.

Quick Start
-----------

.. code-block:: bash

   # Source once in the main script of your library
   source "$(dirname "$0")/config/command_guard.sh"

   cg_guard ls
   ls -l

PATH-safe entry point:

.. code-block:: bash

   source "$(dirname "$0")/config/command_guard.sh"

   my_main() {
       cg_guard uname date
       uname -s
       date -u
   }

   cg_safe_run my_main

Public API
----------

cg_guard
~~~~~~~~

Defines a function named ``<command>`` that forwards to the external command by
full path. Also available as ``guard`` (short alias, defined only if unclaimed —
see *guard alias* below).

- Usage: ``cg_guard [-q] [-p <prefix>] [-r <resolver>] [resolver-opts] [--] [token ...]``
- **Guard options must precede resolver options.** The recommended order is
  ``-p prefix -r resolver resolver-opts tokens``, but ``-r`` and ``-p`` may be
  swapped. All ``-X`` flags that ``cg_guard`` does not recognise are forwarded to the
  active resolver (see *Resolver Protocol*).
- Options:

  - ``-q``: Quiet mode, suppresses warnings for zero tokens.
  - ``-p <prefix>``: Prepend ``prefix`` to the generated function name for
    **plain-name** and **absolute-path** tokens. Has no effect on tokens that
    use the explicit ``fname=…`` form.
  - ``-r <resolver>``: Use ``resolver`` instead of ``cg_safe_resolver`` to
    resolve plain-name and ``fname=name`` (non-absolute RHS) tokens.
  - ``--``: End of options; required when a token name starts with ``-``.
  - Each of ``-q``, ``-p``, and ``-r`` may appear **at most once**; repeating
    any of them is a ``CG_ERR_SYNTAX_ERROR``.

- Token forms (all forms may be mixed in a single call):

  .. list-table::
     :header-rows: 1
     :widths: 35 30 35

     * - Token
       - Generated function name
       - Path source
     * - ``fname=/abs/path``
       - ``fname`` (prefix **not** applied)
       - verbatim absolute path
     * - ``fname=name``
       - ``fname`` (prefix **not** applied)
       - active resolver
     * - ``/abs/path``
       - ``<prefix>basename``
       - verbatim absolute path
     * - ``name``
       - ``<prefix>name``
       - active resolver

  Rules:

  - ``fname`` and plain ``name`` must be valid Bash identifiers
    (``^[a-zA-Z_][a-zA-Z0-9_]*$``).
  - For ``fname=rhs``: if ``rhs`` contains ``/`` but is not absolute, the token
    is rejected (``CG_ERR_SYNTAX_ERROR``).
  - For ``/abs/path``: the basename of the path must be a valid Bash identifier;
    if not (e.g. ``/usr/local/bin/my-cmd``), use the ``fname=/abs/path`` form
    with an explicit identifier.

- Returns:

  - ``0`` on success, including when zero tokens are provided (with optional warning).
  - ``CG_ERR_INVALID_NAME`` when a token contains an invalid Bash identifier.
  - ``CG_ERR_MISSING_ARGUMENT`` when a guard option (``-r`` or ``-p``) is
    present but its required argument is missing.
  - ``CG_ERR_NOT_FOUND`` when a command cannot be resolved or a path is
    invalid or non-executable.
  - ``CG_ERR_SYNTAX_ERROR`` when a relative path is used in the ``fname=rhs``
    form (absolute path required), or when a guard option (``-q``, ``-r``,
    ``-p``) is repeated.

- Validation is all-or-nothing: no wrapper functions are created unless every
  token passes validation.

guard alias
~~~~~~~~~~~

After ``cg_guard`` is defined, the library defines ``guard`` as a short alias:

.. code-block:: bash

   guard() { cg_guard "$@"; }

This alias is installed only if no function named ``guard`` already exists at
source time (same pattern as ``command_not_found_handle``). Applications that
define their own ``guard`` function before sourcing the library will not have it
overwritten. Both names are fully supported; ``cg_guard`` is the canonical name.

cg_safe_run
~~~~~~~~~~~

Executes a declared Bash function under a restricted, read-only PATH. Any
attempt to invoke an unguarded external command inside the function (or any
function it calls) triggers a Bash readonly-assignment failure that aborts the
entire call stack unconditionally.

- Usage: ``cg_safe_run <fn> [args...]``
- ``fn`` must be a declared Bash function (verified with ``declare -f``).
- The fake PATH value is randomised (``SRANDOM`` on Bash 5.1+; ``${-}${RANDOM}``
  fallback) to prevent an attacker from pre-populating ``/nonexistent-<fixed>``
  with malicious symlinks.
- Returns:

  - ``CG_ERR_INVALID_NAME`` if ``fn`` is not a declared function.
  - Hard abort (``CG_ERR_PATH_VIOLATION``) propagating through all callers if
    an unguarded external command is attempted inside ``fn``.
  - Whatever ``fn`` returns on success.

- Use ``cg_unsafe`` to wrap library-initialization code (``cg_guard`` calls) inside
  a ``cg_safe_run`` context.

cg_unsafe
~~~~~~~~~

Executes a function with a writable local PATH set to the compiled-in Bash
default (discovered once at source time via a subshell; never hardcoded).

- Usage: ``cg_unsafe <fn> [args...]``
- Intended for wrapping library ``cg_guard`` calls that must run inside a
  ``cg_safe_run`` context. Because ``local PATH`` in the callee creates a
  new binding that shadows the ``local -r PATH`` from ``cg_safe_run``, no
  error occurs.
- Returns: whatever ``fn`` returns.

cg_safe_resolver
~~~~~~~~~~~~~~~~

The default resolver used by ``cg_guard``. Resolves a command name to its absolute
path using ``command -pv`` (Bash builtin, POSIX default PATH). Accepts no
options; pass all arguments directly to ``cg_guard``.

- Protocol: ``cg_safe_resolver <cmd-name>``
  (see *Resolver Protocol* for the calling convention).
- Returns ``0`` and prints the absolute path on success.
- Returns ``CG_ERR_NOT_FOUND`` on failure (also prints the raw ``command -pv``
  output, which may be ``exec`` for builtins or ``alias …`` for aliases;
  ``cg_guard`` uses this to produce specific diagnostics).
- Returns ``CG_ERR_SYNTAX_ERROR`` with a diagnostic message when called with
  more than one argument (structural misuse; ``cg_guard`` never passes options
  to this resolver).
- Returns ``CG_ERR_MISSING_ARGUMENT`` when called with no arguments.

cg_path_resolver
~~~~~~~~~~~~~~~~

An extended resolver that searches a caller-specified set of directories instead
of the POSIX default PATH.

- Protocol: ``cg_path_resolver [-d dir-or-colon-list] [-s] ... <cmd-name>``
  (see *Resolver Protocol*).
- ``-d <dir-or-colon-list>``: add one or more directories to the search PATH
  (cumulative; ``-d`` may be repeated; its value may be a single directory or a
  colon-separated list such as ``/a:/b:/c``).
- ``-s``: append the compiled-in Bash safe path (equivalent to
  ``-d "$_CG_DEFAULT_PATH"``). Use this option when standard commands must be
  resolved alongside custom directories without referencing the internal
  ``_CG_DEFAULT_PATH`` variable. Option order is respected: ``-s`` inserts the
  safe path at its position in the search order relative to any ``-d`` options.
- Builds a ``local PATH`` from the accumulated directories in the order the
  options appear, then uses ``command -v`` to resolve the command.
- Returns ``0`` and prints the absolute path on success.
- Returns ``CG_ERR_NOT_FOUND`` on failure (command not resolved in the given
  directories).
- Returns ``CG_ERR_SYNTAX_ERROR`` with a diagnostic message when an unexpected
  token appears before the command name.
- Returns ``CG_ERR_MISSING_ARGUMENT`` when called with no command name.

Example — guard a snap binary:

.. code-block:: bash

   cg_guard -r cg_path_resolver -d /snap/bin snapd

Example — snap binary plus standard commands in one call:

.. code-block:: bash

   # -s appends the safe path after /snap/bin, so standard commands are also found:
   cg_guard -r cg_path_resolver -d /snap/bin -s snapd uname date

Example — safe path searched first, custom directory as fallback:

.. code-block:: bash

   cg_guard -r cg_path_resolver -s -d /opt/myapp/bin uname myapp

cg_command_not_found_handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Public handler for the ``command_not_found_handle`` hook. When ``CG_DEBUG`` is
set (non-empty), prints a ``[WARNING]`` message and a ``guard`` suggestion to
stderr; otherwise silent. Always returns 127 (Bash convention for
command-not-found).

- Usage: ``cg_command_not_found_handler <cmd>``
- Applications that define their own ``command_not_found_handle`` may delegate
  to this function as a chaining call:

  .. code-block:: bash

     command_not_found_handle() {
         my_application_handler "$@"
         cg_command_not_found_handler "$@"
     }

- ``command_not_found_handle`` is installed automatically by the library **only**
  if no such function is already defined at source time.

Resolver Protocol
-----------------

A resolver is a function that maps a command name to its absolute path. The
calling convention is:

.. code-block:: text

   resolver_fn [forwarded-opts...] <cmd-name>

- The **last positional argument** is always the command name.
- All preceding arguments are options specific to the resolver.
- On success: print the resolved absolute path to stdout; return 0.
- On failure: return non-zero. The function **should** print the raw
  ``command -v`` (or equivalent) output even on failure, so that ``cg_guard``
  can distinguish builtins, aliases, and truly missing commands.
- **Required contract**: when called with no command name (all arguments were
  consumed as option parameters), the resolver **must** return
  ``CG_ERR_MISSING_ARGUMENT``. ``cg_guard`` uses this to determine which
  forwarded options take an argument, via a probe call (see ``cg_guard`` option
  forwarding).
- Resolvers must be **pure** (no side effects). ``cg_guard`` discards probe-call
  results.

Custom resolver example:

.. code-block:: bash

   my_resolver() {
       # forwarded-opts are ignored; last arg is the command name
       local cmd="${@: -1}"
       local resolved="/opt/myapp/bin/$cmd"
       printf '%s' "$resolved"
       [[ -x "$resolved" ]] || return "$CG_ERR_NOT_FOUND"
   }

   cg_guard -r my_resolver mytool

PATH Enforcement
----------------

``cg_safe_run`` restricts PATH to a non-existent random value for the duration
of the called function. Any unguarded external command inside that function
causes Bash to emit:

.. code-block:: text

   bash: PATH: readonly variable

and abort the entire call stack back to the top-level script. This is a
**hard abort** — it cannot be intercepted with ``|| true``, ``{ }`` grouping,
or any amount of function nesting.

Guarded commands are unaffected because their wrapper functions dispatch by
absolute path and do not use PATH.

Library authors should wrap their ``cg_guard`` initialisation in ``cg_unsafe``:

.. code-block:: bash

   my_lib_init() {
       cg_unsafe cg_guard uname date hostname
       # ... other initialisation
   }

   my_lib_main() {
       my_lib_init
       uname -s
   }

   cg_safe_run my_lib_main

``CG_DEBUG=1`` enables the ``command_not_found_handle`` warning and suggestion
output. It is safe to enable in development but should be unset in production.

Error Codes
-----------

- ``CG_ERR_PATH_VIOLATION=1``: Bash readonly-assignment failure exit code.
  Produced by the Bash runtime, not by library code. The constant is provided
  for documentation and test assertions only.
- ``CG_ERR_NOT_FOUND=3``: command not found, path invalid, or non-executable.
- ``CG_ERR_INVALID_NAME=5``: invalid Bash identifier (aligned with
  ``HS_ERR_INVALID_VAR_NAME``).
- ``CG_ERR_MISSING_ARGUMENT=8``: required argument missing — no command name
  supplied to a resolver, or a guard option ``-r``/``-p`` is missing its
  argument (aligned with ``HS_ERR_MISSING_ARGUMENT``).
- ``CG_ERR_SYNTAX_ERROR=9``: structural calling-convention violation — function
  called with the wrong number or type of arguments, or a path that violates a
  structural constraint (e.g. relative path where absolute is required) (aligned
  with ``HS_ERR_INVALID_ARGUMENT_TYPE``).

Behavior Details
----------------

Command resolution by ``cg_safe_resolver`` uses ``command -pv``, which uses the
Bash builtin restricted default PATH independently of the ``$PATH`` variable.

``cg_path_resolver`` uses ``command -v`` with a ``local PATH`` built from the
caller-supplied directories. It does not fall back to the POSIX default PATH;
list all required directories explicitly.

It is an error to call ``cg_guard`` on aliases and shell builtins. An error
message is printed to stderr and the script is aborted.

Subshells will be exited but the overall script may continue to run. Avoid
constructs that generate subshells in favour of returning results via
out-variables:

.. code-block:: bash

   myfunction() {
       local arg1=$1
       local -n out=$2
       # ... compute result ...
       out=$result
   }

   if myfunction "$arg" result; then
       : # use "$result"
   else
       : # handle failure
   fi

Developer Reference
-------------------

.. warning::

   The items in this section are internal implementation details not part of the
   public API. They may change without notice.

_CG_DEFAULT_PATH
~~~~~~~~~~~~~~~~

Set once at source time:

.. code-block:: bash

   _CG_DEFAULT_PATH="$(unset PATH; "$(command -pv bash)" -c 'echo "$PATH"')"

Contains the compiled-in Bash default PATH (the value Bash uses when PATH is
unset). Used by ``cg_unsafe`` to restore a writable PATH inside a
``cg_safe_run`` context without hardcoding a PATH string.

Known Limitations
-----------------

- ``cg_safe_run`` hard-aborts the entire script on a PATH violation; there is no
  mechanism to catch or recover from it. This is by design.
- ``cg_path_resolver`` searches only the directories supplied via ``-d`` and/or
  ``-s``. It does not fall back to the POSIX default PATH unless ``-s`` is
  present; list all required directories explicitly or add ``-s`` to include
  the standard locations.
- The ``command_not_found_handle`` hook is a single global resource. The library
  installs it only if unclaimed; applications that need their own handler should
  define it before sourcing the library, or chain via
  ``cg_command_not_found_handler``.
- The ``guard`` alias is a single global resource. The library defines it only
  if unclaimed; applications that define their own ``guard`` function before
  sourcing the library will keep their version. Use ``cg_guard`` directly when
  ``guard`` may be claimed.

Examples
--------

Guarding standard commands:

.. code-block:: bash

   source "$(dirname "$0")/config/command_guard.sh"
   cg_guard uname date hostname
   uname -s

Guarding with an explicit path:

.. code-block:: bash

   cg_guard "myuname=/usr/bin/uname"
   myuname -s

Guarding with a prefix (library namespace isolation):

.. code-block:: bash

   cg_guard -p mylib_ uname date
   mylib_uname -s

Guarding a snap binary by absolute path token:

.. code-block:: bash

   cg_guard /snap/bin/snapd

Guarding a binary whose filename is not a valid identifier:

.. code-block:: bash

   cg_guard "bash5=/usr/bin/bash5.0"

Full ``cg_safe_run`` pattern with library initialisation:

.. code-block:: bash

   source "$(dirname "$0")/config/command_guard.sh"

   _my_init() {
       cg_unsafe cg_guard uname date
   }

   _my_main() {
       _my_init
       uname -s
       date -u
   }

   CG_DEBUG=1 cg_safe_run _my_main

Source Listing
--------------

.. literalinclude:: ../../config/command_guard.sh
   :language: bash
   :linenos:
