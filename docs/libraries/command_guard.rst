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

       cg_guard -r cg_path_resolver -s "$(cg_search_snaps)" docker

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

Asynchronous Use
----------------

Every wrapper function generated by ``cg_guard`` is safe to background with
``&``, use inside command substitution ``$(…)``, pipeline stages, and coproc.
The foreground path is a transparent pass-through identical to the unguarded
binary call. The behaviour below applies only when the wrapper runs in a
subshell context.

**Why backgrounded commands inside** ``$(…)`` **can block the substitution.**
``$(…)`` works by connecting bash's reader to one end of a kernel pipe and the
substitution body's stdout to the other end. Bash reads until the pipe delivers
EOF. EOF arrives only when *every* process that holds the write end has closed
it. A command started with ``&`` inside ``$(…)`` forks a child that inherits
fd 1 — the write end of the capture pipe. The main body finishes and bash
closes its copy of the write end, but the background child still holds the pipe
open. Bash cannot see EOF and cannot return from ``$(…)`` until that child also
closes fd 1 — whether by exiting normally, being killed, or explicitly
redirecting its stdout. With a guarded command this is aggravated because the
child that holds the pipe is the binary itself, whose PID is not directly
reachable through ``$!`` without the mechanism described in *Capture pipe
safety* below.

How the wrapper detects a subshell context
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The wrapper tests ``$BASHPID != $$``. This condition is true in every subshell
context — ``&``, ``$(…)``, pipeline stages (including the last stage with
``shopt -s lastpipe`` disabled), and coproc — and false when the wrapper runs
directly in the calling shell. When false the wrapper forwards directly to the
binary with no extra forks or traps.

Kill propagation
~~~~~~~~~~~~~~~~

When the caller backgrounds a guarded command and later sends a signal to
``$!``, the signal reaches the actual binary:

.. code-block:: bash

   cg_guard nc
   nc -lU "$sock" <&"$fd_in" >&"$fd_out" &
   nc_pid=$!
   # … later …
   kill         "$nc_pid"   # SIGTERM forwarded to /usr/bin/nc
   kill -INT    "$nc_pid"   # binary terminated via SIGTERM (see note below)
   kill -HUP    "$nc_pid"   # SIGHUP  forwarded to /usr/bin/nc
   wait         "$nc_pid"   # exit status reflects binary's termination

The wrapper installs forwarding traps for SIGTERM, SIGINT, and SIGHUP, and an
EXIT trap as a backstop. The EXIT trap fires even on unhandled signals or
unexpected wrapper exits, ensuring the binary is never left as an orphan.

.. note::

   **SIGINT and background processes.** POSIX specifies that asynchronous
   commands in non-interactive shells have SIGINT set to SIG_IGN. Because the
   binary is started with ``&`` inside a subshell that is itself a background
   job, it inherits SIG_IGN for SIGINT. Forwarding SIGINT to it would be
   silently discarded. The INT trap therefore sends SIGTERM to the binary,
   which is not subject to SIG_IGN. The net effect — the binary is terminated
   when the caller sends ``kill -INT $!`` — is the same; only the signal
   received by the binary differs.

SIGKILL cannot be trapped. Sending ``kill -9 $!`` terminates the wrapper
subshell without propagating to the binary; callers that need unconditional
teardown should use a process group kill (``kill -- -$pgid``) with job control
enabled (``set -m``).

Signals that have no trap in the wrapper (e.g. SIGUSR1) reach the wrapper with
the default action (typically terminate). The EXIT trap then kills the binary
cleanly.

Capture pipe safety
~~~~~~~~~~~~~~~~~~~

A guarded command backgrounded inside ``$(…)`` does not hold the capture pipe
open after the caller kills it. The EXIT trap kills the binary promptly, so the
pipe is released and the substitution returns:

.. code-block:: bash

   cg_guard sleep
   result=$(
       sleep 10 &
       job_pid=$!
       do_work
       kill "$job_pid"    # EXIT trap kills /usr/bin/sleep → pipe released
       echo "done"
   )
   # $result == "done"; substitution returns promptly

Without the trap the orphaned binary holds fd 1 (the capture pipe) open until
it exits on its own, blocking the substitution for the full remaining duration
of the binary's execution.

Constructs supported
~~~~~~~~~~~~~~~~~~~~

The following constructs all behave correctly after the fix:

.. list-table::
   :header-rows: 1
   :widths: 45 55

   * - Construct
     - Notes
   * - ``wrapped_cmd args &``
     - Standard backgrounding; ``$!`` is the wrapper subshell PID.
   * - ``wrapped_cmd args >/dev/null &``
     - Stdout redirect applied before wrapper body runs; still propagates kill.
   * - ``{ wrapped_cmd args; } &``
     - Brace group forks one subshell; ``$BASHPID != $$`` triggers the gate.
   * - ``: | wrapped_cmd args &``
     - Wrapper runs as the last pipeline stage in its own subshell.
   * - ``coproc CPROC { wrapped_cmd args; }``
     - ``$CPROC_PID`` is the wrapper subshell PID; same trap mechanism applies.
   * - ``set -m; wrapped_cmd args &``
     - Job control assigns a new process group; kill propagation is unchanged.
   * - ``out=$(wrapped_cmd args &; …)``
     - Capture pipe is released when ``kill $!`` fires the EXIT trap.
   * - ``cmd1 & p1=$!; cmd2 & p2=$!``
     - Each wrapper subshell has its own independent trap state; concurrent
       backgrounding of the same or different guarded commands is safe.

stdin of the binary
~~~~~~~~~~~~~~~~~~~

When the wrapper is called in a shell with job control inactive (the default
for non-interactive shells and all subshells), the inner ``&`` redirects the
binary's stdin to ``/dev/null``. In practice this is the same value the wrapper
subshell itself received from the outer ``&``, so the binary's stdin is
``/dev/null`` in all normal backgrounding contexts.

Callers that need the binary to read from a specific fd should redirect at the
call site (``wrapped_cmd <&"$fd_in" &``); the redirect is applied to the wrapper
subshell before the wrapper body runs and the binary inherits it.

Wait loop and signal-interrupted wait
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Bash's ``wait`` builtin returns early (exit code > 128) when a trapped signal
arrives, even if the binary is still running. The wrapper retries ``wait`` in a
loop until the binary is confirmed dead:

.. code-block:: text

   wait "$_cg_p" || _cg_rc=$?
   while (( _cg_rc > 128 )) && kill -0 "$_cg_p" 2>/dev/null; do
       wait "$_cg_p" || _cg_rc=$?
   done

This covers the case where the binary ignores or handles the forwarded signal
and continues running. Without the loop the wrapper would return prematurely
and orphan the binary.

The ``|| _cg_rc=$?`` form is used throughout rather than a plain assignment so
that the wrapper body is safe when the caller has ``set -e`` active. The library
does not control ``set -e`` or ``inherit_errexit``; the ``||`` prevents errexit
from firing before the exit code is captured.

Exit status
~~~~~~~~~~~

The wrapper propagates the binary's exit status through ``wait``:

.. code-block:: bash

   cg_guard sleep
   sleep 0 &
   wait "$!"        # returns 0 (sleep exited normally)

   sleep invalid &
   wait "$!"        # returns 1 (sleep rejected the argument)

Compatibility with shell options
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The wrapper body is designed to work correctly regardless of the caller's
active shell options. The library does not set or clear any shell option.

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Option
     - Effect on wrapper
   * - ``set -e`` / ``inherit_errexit``
     - Handled by ``wait … \|\| _cg_rc=$?``; errexit cannot fire mid-capture.
   * - ``set -u``
     - All wrapper locals (``_cg_p``, ``_cg_rc``) are initialised before use.
   * - ``shopt -s lastpipe``
     - When the last pipeline stage runs in the main shell, ``$BASHPID == $$``
       and the direct branch executes. No indirection is needed: the binary is
       already a direct child of the calling shell.
   * - ``set -m`` (job control)
     - The wrapper subshell may receive a new process group; the EXIT and signal
       traps are unaffected.

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

Change History
--------------

.. list-table::
   :header-rows: 1
   :widths: 10 90

   * - PR
     - Summary
   * - #8
     - initial documentation
   * - #23
     - feature/skills update
   * - #113
     - name=path guard token syntax [closes #111]
   * - #114
     - PATH enforcement API -- cg_safe_run, cg_unsafe [closes #112]
   * - #118
     - name filter and snap search API [closes #116, #117]
   * - #127
     - gated trap-EXIT wrapper for async kill-propagation [closes #127]
