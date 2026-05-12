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

- Usage: ``cg_guard [-q] [-n <name_filter>] [-p <value>] [-r <resolver>] [-z <packed>] [resolver-opts] [--] [token ...]``
- **Guard options must precede resolver options.** The recommended order is
  ``-n filter -p value -r resolver resolver-opts tokens``. All ``-X`` flags that
  ``cg_guard`` does not recognise are forwarded to the active resolver
  (see *Resolver Protocol*).
- Options:

  - ``-q``: Quiet mode, suppresses warnings.
  - ``-n <name_filter>``: Use ``name_filter`` instead of the default
    ``cg_mkfname_prefix`` to compute the wrapper function name for **plain-name**
    and **absolute-path** tokens. Has no effect on ``fname=…`` tokens. See
    *Name Filter Protocol*. May appear **at most once**.
  - ``-p <value>``: Set the name filter parameter(s). For the default
    ``cg_mkfname_prefix`` filter, ``value`` is the prefix string prepended to the
    bare name. For custom filters, ``value`` is a packed parameter list (see
    *Name Filter Protocol — packed value syntax*). An empty ``-p ""`` with the
    default filter emits a ``[WARNING]`` unless ``-q`` is active. Has no effect
    on ``fname=…`` tokens. May appear **at most once**.
  - ``-r <resolver>``: Use ``resolver`` instead of ``cg_safe_resolver`` to
    resolve plain-name and ``fname=name`` (non-absolute RHS) tokens.
  - ``-z <packed>``: Unpack ``packed`` and inject the resulting tokens back into
    the option-parsing loop at the current position, as if they had been written
    on the command line. The value is parsed by the packed-value convention (see
    *Name Filter Protocol — packed value syntax*). May be **repeated**; each
    occurrence injects one independent batch. Primary use: pass
    ``cg_search_snaps`` output to the active resolver:

    .. code-block:: bash

       cg_guard -r cg_path_resolver "$(cg_search_snaps)" docker

  - ``--``: End of options; required when a token name starts with ``-``.
  - Each of ``-q``, ``-n``, ``-p``, and ``-r`` may appear **at most once**;
    ``-z`` may be repeated. Repeating ``-q``, ``-n``, ``-p``, or ``-r`` is a
    ``CG_ERR_SYNTAX_ERROR``.

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
    form (absolute path required); when a guard option (``-q``, ``-n``, ``-r``,
    ``-p``) is repeated; or when a forwarded option flag is rejected by the
    active resolver as unrecognised (probe returns ``CG_ERR_SYNTAX_ERROR``).
  - The name filter's own exit code when the filter rejects a token. The filter
    is responsible for its own diagnostic message.

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
- Intended for wrapping third-party init functions that modify or rely on
  ``$PATH`` during initialisation — code the caller does not control and
  that would fail under ``cg_safe_run``'s read-only PATH. ``cg_guard``
  itself never needs ``cg_unsafe``: both ``cg_safe_resolver`` and
  ``cg_path_resolver`` establish their own PATH independently.
- **Why it is needed inside** ``cg_safe_run``: third-party libraries
  sometimes set or rely on ``$PATH`` during initialisation; under
  ``cg_safe_run`` the PATH is read-only and such libraries would abort.
  ``cg_unsafe`` locally reverses the restriction for the duration of the
  called function, then the restriction is reinstated automatically when
  the function returns.
- **Risk**: ``cg_unsafe`` restores a *writable* PATH set to the
  compiled-in Bash default — not the full system PATH, but enough to
  find most standard commands. Any unguarded command reachable on that
  PATH will execute silently, without triggering
  ``cg_command_not_found_handle``. This suspends the enforcement guarantee
  of ``cg_safe_run`` for the entire duration of the called function.
  Keep the scope as narrow as possible. Because any PATH extension made
  by the third-party init lives only inside the ``local PATH`` binding of
  ``cg_unsafe`` — it is discarded when ``cg_unsafe`` returns — ``$PATH``
  must be captured while still inside that scope. ``cg_guard`` never reads
  ``$PATH`` on its own; the extended directories must always be passed
  explicitly via ``-d "$PATH"`` to ``cg_path_resolver``. The wrapper must
  therefore either call ``cg_guard -r cg_path_resolver -d "$PATH" ...``
  from within its own body, or capture ``$PATH`` into a variable and
  return it so the caller can pass it as ``-d``.
- Typical use: an init wrapper that calls the third-party init (which may
  extend PATH), then immediately calls ``cg_guard -r cg_path_resolver -d "$PATH"``
  to register the commands it discovered — all inside the wrapper passed
  to ``cg_unsafe``. Example: a library whose binaries live in
  ``/opt/optlib/bin`` but whose init script is installed in ``/usr/bin``:

  .. code-block:: bash

     # optlib_wrapper.sh — source this to initialise optlib in a guarded app.

     # Guard the init script via cg_safe_resolver (uses command -pv; no
     # cg_unsafe needed even inside cg_safe_run).
     cg_guard optlib_init

     _optlib_init_wrapper() {
         # optlib_init extends PATH to include /opt/optlib/bin.
         optlib_init
         # Guard its commands while the PATH extension is still live.
         cg_guard -r cg_path_resolver -d "$PATH" optfoo optbar
     }

     # cg_unsafe makes PATH writable so optlib_init can extend it.
     # Binaries guarded above are callable safely after this line.
     cg_unsafe _optlib_init_wrapper

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
  more than one argument (structural misuse; any attempt to forward a resolver
  option while ``cg_safe_resolver`` is active causes ``cg_guard`` to abort
  with ``CG_ERR_SYNTAX_ERROR`` via the probe mechanism).
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

Example — guard a binary installed in a custom directory:

.. code-block:: bash

   cg_guard -r cg_path_resolver -d /opt/myapp/bin myapp

Example — custom directory plus standard commands in one call:

.. code-block:: bash

   # -s appends the safe path after /opt/myapp/bin so both are reachable:
   cg_guard -r cg_path_resolver -d /opt/myapp/bin -s myapp uname date

.. note::
   For snap binaries, use :func:`cg_search_snaps` to discover the snap bin
   directory at runtime rather than hard-coding it here.

Example — safe path searched first, custom directory as fallback:

.. code-block:: bash

   cg_guard -r cg_path_resolver -s -d /opt/myapp/bin uname myapp

cg_command_not_found_handle
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Public handler for the ``command_not_found_handle`` hook. When ``CG_DEBUG`` is
set (non-empty), prints a ``[WARNING]`` message and a ``guard`` suggestion to
stderr; otherwise silent. Always returns 127 (Bash convention for
command-not-found).

- Usage: ``cg_command_not_found_handle <cmd>``
- Applications that define their own ``command_not_found_handle`` may delegate
  to this function as a chaining call:

  .. code-block:: bash

     command_not_found_handle() {
         my_application_handler "$@"
         cg_command_not_found_handle "$@"
     }

- ``command_not_found_handle`` is installed automatically by the library **only**
  if no such function is already defined at source time.

cg_mkfname_prefix
~~~~~~~~~~~~~~~~~

The default name filter used by ``cg_guard``. Prepends a fixed prefix to the
bare command name and validates the result as a legal Bash identifier.

- Usage: ``cg_mkfname_prefix <prefix> <bare-name>``
- Always receives exactly 2 arguments: ``$1`` is the prefix (possibly empty)
  and ``$2`` is the bare name. This matches the calling convention established
  by ``cg_guard`` — the default ``-p ""`` always supplies an empty-string
  prefix.
- Prints the concatenated ``prefix + bare-name`` on success; returns 0.
- Returns ``CG_ERR_SYNTAX_ERROR`` with a diagnostic if the argument count is
  not exactly 2.
- Returns ``CG_ERR_INVALID_NAME`` with a diagnostic if the result is not a
  valid Bash identifier (``^[a-zA-Z_][a-zA-Z0-9_]*$``).

When used as the default filter with no ``-p``, ``cg_guard`` passes ``""`` as
the prefix, so the wrapper function name equals the bare command name.

cg_search_snaps
~~~~~~~~~~~~~~~

Discovers the snap binary directory and returns it as a ``-z``-packed argument
suitable for passing directly to ``cg_guard -r cg_path_resolver``.

- Usage: ``"$(cg_search_snaps)"`` — always use quoted command substitution.
- Always outputs a string starting with ``-z`` (never empty):

  - ``$'-z\x1F'`` when snap is absent or ``snap debug paths`` does not yield a
    usable ``SNAPD_BIN`` directory. This is a no-op injection: the ``-z`` case
    in ``cg_guard`` injects nothing and processing continues normally.
  - ``$'-z\x1F-d\x1F/snap/bin'`` (actual path from ``SNAPD_BIN``) when snap is
    present and the directory exists.

- Emits a ``[WARNING]`` to stderr when the ``snap`` binary is found but
  ``snap debug paths`` fails or ``SNAPD_BIN`` is missing or not a directory.
- Returns 0 in all cases.

Typical usage:

.. code-block:: bash

   cg_guard -r cg_path_resolver "$(cg_search_snaps)" docker compose

Because ``cg_search_snaps`` always outputs a ``-z``-prefixed value, it is safe
to use unconditionally; when snap is absent the argument is a no-op.

The snap binary directory is appended at the position ``cg_search_snaps``
appears in the ``cg_guard`` argument list, **after** any preceding ``-d``
options. This matches the snap convention: the snap paths directory is added
at the end of PATH by the snap package itself.

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

Name Filter Protocol
--------------------

A name filter is a function that computes the wrapper function name from a
set of filter parameters and a bare command name. The calling convention is:

.. code-block:: text

   filter_fn [params...] <bare-name>

- The **last positional argument** is always the bare name.
- All preceding arguments are the filter parameters supplied via ``-p``.
- On success: print the wrapper function name to stdout; return 0. The result
  must be a valid Bash identifier (``^[a-zA-Z_][a-zA-Z0-9_]*$``).
- On failure: print a diagnostic to stderr; return non-zero. The exit code is
  propagated directly to the ``cg_guard`` caller.

The default filter is ``cg_mkfname_prefix``. It always receives exactly 2
arguments: an empty or non-empty prefix string, and the bare name.

Packed value syntax (``-p`` and ``-z``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Both ``-p`` and ``-z`` use the same packed-value convention:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - First character of value
     - Interpretation
   * - ``[a-zA-Z0-9_-]``
     - Single element; the whole value is passed through as-is.
   * - ``""`` (empty string)
     - Single empty-string element (one ``""`` argument to the filter).
   * - Any other character (e.g. ``:``, ``\x1F``)
     - That character is the separator. Strip it; split the remainder on it.
       Empty results from splitting are dropped.

Examples:

.. code-block:: bash

   # -p "pfx_"          → filter receives: "pfx_"  bare_name
   # -p ""              → filter receives: ""       bare_name  (+ warning with default filter)
   # -p ":run_:_cb"     → filter receives: "run_"  "_cb"  bare_name
   # -p $'\x1Fa\x1Fb'  → filter receives: "a"     "b"    bare_name

Custom name filter example:

.. code-block:: bash

   my_filter() {
       local prefix="$1" bare_name="$2"
       local fname="${prefix}${bare_name}"
       [[ "$fname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
           echo "[ERROR] my_filter: '${fname}' is not a valid identifier." >&2
           return "$CG_ERR_INVALID_NAME"
       }
       printf '%s' "$fname"
   }

   cg_guard -n my_filter -p "my_" uname date

PATH Enforcement
----------------

``cg_safe_run`` restricts PATH to a non-existent random value for the duration
of the called function.

**Unguarded external commands** fail with exit code 127 (command not found).
The installed ``command_not_found_handle`` is invoked; with ``CG_DEBUG=1`` it
prints a warning and a ``cg_guard`` suggestion to stderr. The caller receives
127 and may handle it normally.

**Any attempt to assign to PATH** inside the called function causes Bash to
emit:

.. code-block:: text

   bash: PATH: readonly variable

and returns exit code 1 (``CG_ERR_PATH_VIOLATION``).

Guarded commands are unaffected because their wrapper functions dispatch by
absolute path and do not use PATH.

The typical use case is wrapping a third-party library whose init modifies
PATH to expose its binaries. Write an init wrapper that runs the library
init under ``cg_unsafe`` (so PATH is writable and arbitrary commands can
run), then guards the discovered binaries with ``cg_path_resolver -d``:

.. code-block:: bash

   _my_lib_init_wrapper() {
       # PATH is writable here; third_party_init may extend it freely.
       third_party_init
       # Guard the library's commands by the directory it installed to.
       cg_guard -r cg_path_resolver -d /opt/mylib/bin cmd1 cmd2
   }

   my_main() {
       cg_unsafe _my_lib_init_wrapper
       cmd1 --version
   }

   cg_safe_run my_main

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
  ``cg_command_not_found_handle``.
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

Guarding with a custom name filter:

.. code-block:: bash

   my_filter() { printf '%s' "${1}${2}"; }   # same as default but custom
   cg_guard -n my_filter -p "ns_" uname date
   ns_uname -s

Guarding a tool that may be installed as a snap or system package:

.. code-block:: bash

   cg_guard -r cg_path_resolver -s "$(cg_search_snaps)" docker

Guarding a snap binary by absolute path token:

.. code-block:: bash

   cg_guard /snap/bin/snapd

Guarding a binary whose filename is not a valid identifier:

.. code-block:: bash

   cg_guard "bash5=/usr/bin/bash5.0"

Full ``cg_safe_run`` pattern — guard at initialisation time, enforce at runtime:

.. code-block:: bash

   source "$(dirname "$0")/config/command_guard.sh"

   # Guard external commands once, before entering the safe region.
   # cg_safe_resolver uses command -pv, which reinstates the POSIX default
   # PATH regardless of the local $PATH set by cg_safe_run.
   cg_guard uname date hostname

   _my_main() {
       uname -s
       date -u
   }

   cg_safe_run _my_main

Guarding a tool that may be installed via apt or snap inside ``cg_safe_run``:

.. code-block:: bash

   source "$(dirname "$0")/config/command_guard.sh"

   _my_init() {
       # cg_guard uses command -pv internally; no cg_unsafe needed inside cg_safe_run.
       cg_guard uname date
       # docker-compose may be an apt or snap package; cg_search_snaps handles both.
       cg_guard -r cg_path_resolver -s "$(cg_search_snaps)" docker-compose
   }

   _my_main() {
       _my_init
       uname -s
       docker-compose version
   }

   cg_safe_run _my_main

Source Listing
--------------

.. literalinclude:: ../../config/command_guard.sh
   :language: bash
   :linenos:
