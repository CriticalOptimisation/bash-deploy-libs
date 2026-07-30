Remote Run Library
==================

Location
--------

- ``config/remote_run.sh``

Purpose
-------

This library provides a ``rr_run`` entry point which executes a local shell
script on a remote host via SSH **without writing any file to the remote
filesystem**.  The main script and every library it ``source``\s are kept on
the local machine; the remote side receives file content on demand through a
private TCP channel established by SSH port-forwarding.

The library is designed for scripts that are already validated locally and use
``source`` as their composition mechanism (e.g. ``handle_state.sh``,
``command_guard.sh``).

Dependencies
------------

+------------------+----------+-------------------------------------------+
| Dependency       | Side     | Notes                                     |
+==================+==========+===========================================+
| Bash ≥ 4.3       | Both     | Nameref (``local -n``) in                 |
|                  |          | ``handle_state.sh``; auto-assigned FDs    |
|                  |          | (``exec {var}<>file``) in remote_run.sh   |
+------------------+----------+-------------------------------------------+
| OpenSSH client   | Local    | ``ssh``, ``-T``, ``-R`` required          |
+------------------+----------+-------------------------------------------+
| OpenSSH server   | Remote   | ``sshd`` must be running and reachable    |
+------------------+----------+-------------------------------------------+
| ``nc``           | Local    | OpenBSD nc (``-lU socket``); other        |
|                  |          | variants are not supported                |
+------------------+----------+-------------------------------------------+
| ``base64``       | Remote   | Standard on all major Linux distributions |
+------------------+----------+-------------------------------------------+

All local-side dependencies are checked when the library is sourced via
``cg_guard``.  If any required tool is absent the library fails to load,
emits a diagnostic, and returns ``RR_ERR_DEPENDENCY_MISSING``.

Architecture Overview
---------------------

``rr_run`` establishes a ControlMaster connection and multiplexes two
operations over it.  Each concurrent ``rr_resolve`` call adds a third
channel for the duration of its file transfer, then closes it at EOF:

**Bootstrap channel (SSH stdin via** ``-T``\ **)** — delivers the bootstrap
shell fragment to the remote bash.  The fragment is piped via process
substitution; the write end closes when the generator exits, signalling EOF
to remote bash stdin after the last bootstrap command.  No PTY is allocated;
``ssh -T`` is always used.

**Protocol channel (TCP via SSH** ``-R``\ **)** — carries the file-serving
protocol after the bootstrap is running.  Each ``rr_run`` call starts a
``nc`` listener on an ephemeral Unix-domain socket.  SSH forwards an
auto-allocated remote TCP port to that socket.  The remote bash opens that
port directly using Bash's built-in ``/dev/tcp/localhost/<port>`` path with
``exec {fd}<>/dev/tcp/…``; no SSH client and no additional tool is required
on the remote side.  All subsequent ``GET`` / ``RESOLVE`` / ``OK`` / ``ERR``
messages travel over that single bidirectional file descriptor.

::

    local bootstrap pipe ──► SSH -T stdin ──► remote bash stdin (bootstrap)

    local nc server ◄── SSH -R tunnel ◄── remote bash fd (protocol)
      (GET / RESOLVE / OK / ERR)

The remote bootstrap, delivered via SSH stdin, performs the
following steps before any user code runs:

1. Allocates the protocol file descriptor dynamically (``exec {fd}<>``).
2. Generates and evaluates the ``source`` override with the fd value inscribed
   literally, so that ``source`` works correctly regardless of what the
   user script does to shell variables.
3. Propagates the local shell flags (``$-``) from the ``rr_run`` call site
   so that ``set -x``, ``set -e``, ``set -u``, ``set -o pipefail`` etc. are
   active on the remote if and only if they were active locally.  Note that
   the remote script may subsequently change these flags at any time, exactly
   as it would when run locally.  ``PS4`` is configured to display real source
   paths rather than internal wrapper names when tracing is active.
4. Runs the user script inside the double wrapper (see below).

Quick Start
-----------

.. code-block:: bash

   # Source the library once
   source "$(dirname "$0")/config/remote_run.sh"

   # Run a local script on a remote host (no prior initialisation needed)
   rr_run user@host deploy.sh --env production

   # Capture default options once, then run in parallel on multiple hosts
   local state
   rr_init -S state --ssh-opt "-i ~/.ssh/deploy_key" --allow /opt/shared/libs
   for host in "${servers[@]}"; do
       rr_run -S state "root@$host" deploy.sh --env production &
   done
   wait

Inside ``deploy.sh`` or any script it sources, ``source`` works exactly as
locally:

.. code-block:: bash

   #!/usr/bin/env bash
   source config/handle_state.sh     # fetched from local machine on demand
   source config/command_guard.sh    # nested source — also fetched locally

   guard curl jq

   init_deployment() {
       local endpoint="$1"
       # ... deployment logic ...
   }

   init_deployment "$1"

Public API
----------

rr_init
~~~~~~~

.. code-block:: text

   rr_init -S <var> [--allow <path>] [--ssh-opt <opt>]

Captures default options into a ``handle_state`` vector by name.  Calling
``rr_init`` at all is optional — ``rr_run`` works without it and falls back to
built-in defaults — but when it is called, ``-S`` is mandatory.  The state
vector is the only output ``rr_init`` produces, so a call without ``-S`` would
discard every option it was given.

``-S <var>``
    **Mandatory.**  Name of the caller-owned variable that will receive the
    updated state vector.  Declare ``local <var>`` before calling ``rr_init``.
    Omitting it, supplying it without a value, or supplying it twice is a
    structural call error: the function prints a diagnostic and its synopsis on
    stderr, returns a named error constant, and leaves the state variable
    untouched.

``--allow <path>``
    Default whitelist entry.  May be repeated.

``--ssh-opt <opt>``
    Default SSH option.  May be repeated.

**Exit code**

+------------------------------------+-------------------------------------------+
| Constant                           | Condition                                 |
+====================================+===========================================+
| ``RR_ERR_MULTIPLE_STATE_INPUTS``   | ``-S`` supplied more than once            |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_STATE_VAR``       | ``-S`` absent                             |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_ARGUMENT``        | ``-S`` supplied without a value           |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_UNKNOWN_ARGUMENT``        | Unrecognised option in the option loop    |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_PATH_RESOLUTION_FAILED``  | ``realpath`` failed on an ``--allow`` arg |
+------------------------------------+-------------------------------------------+

rr_run
~~~~~~

.. code-block:: text

   rr_run [-S <var>] [--allow <path>] [--ssh-opt <opt>] [--] <user@host> <script.sh> [args...]

Executes ``<script.sh>`` on ``<user@host>`` via SSH.  All ``source`` calls
inside the script resolve against the local filesystem.  Each call allocates
its own fd and ``nc`` instance; multiple ``rr_run`` calls may run in parallel
against different hosts.

``-S <var>``
    State vector produced by ``rr_init``.  Options in the vector are used as
    defaults and may be overridden by per-call ``--allow`` / ``--ssh-opt``.

``--allow <path>``
    Permit access to ``<path>`` in addition to the whitelist.  May be
    repeated.  Relative paths are resolved against the local working directory
    at invocation time.

``--ssh-opt <opt>``
    Pass an extra option to every ``ssh`` invocation.  May be repeated:

    .. code-block:: bash

       rr_run --ssh-opt "-p 2222" \
              --ssh-opt "-i ~/.ssh/deploy_key" \
              --ssh-opt "-o StrictHostKeyChecking=no" \
              user@host deploy.sh

``<user@host>``
    SSH target.  Any format accepted by ``ssh`` is valid.

``<script.sh>``
    Path to the local script to execute, or a ``/dev/fd/N`` path produced by
    ``rr_resolve`` for relay scenarios.

``[args...]``
    Positional arguments forwarded to the script as ``$1``, ``$2``, …

**Exit code**

Returns the exit code of the remote script, or one of the named error
constants defined in the **Error Codes** section below:

+------------------------------------+-------------------------------------------+
| Constant                           | Condition                                 |
+====================================+===========================================+
| ``RR_ERR_UNKNOWN_ARGUMENT``        | Unrecognised option in the option loop    |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_ARGUMENT``        | ``<user@host>`` absent                    |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_SCRIPT_ARGUMENT`` | ``<script.sh>`` absent                    |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_PATH_RESOLUTION_FAILED``  | ``realpath`` failed on an ``--allow`` arg |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_SCRIPT_NOT_FOUND``        | Script file not found or not readable     |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_SSH_CONNECT_FAILED``      | ControlMaster connection failed           |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_PORT_FORWARD_FAILED``     | ``-O forward`` port allocation failed     |
+------------------------------------+-------------------------------------------+

HS error codes 1–12 may also be returned when ``-S`` state-read operations
propagate a failure via ``|| return $?``.

rr_resolve
~~~~~~~~~~

.. code-block:: text

   rr_resolve [-S <state>] <file>

Makes a local file available as a readable file descriptor and prints the
corresponding ``/dev/fd/N`` path.  The behaviour depends on which machine
the function runs on:

**On the originating machine (A):** no-op; returns the file path unchanged.

**On a relay machine (B, running a script fetched from A):** sends a
``RESOLVE <path>`` request on the protocol channel back to A.  A opens a
dedicated ``nc`` listener on a new ephemeral port and establishes a second
SSH ``-R`` tunnel to B for that port.  A signals readiness with
``RESOLVE_OK <port>`` only after the tunnel is active (synchronised via
ControlMaster ``-O forward``).  B allocates a new fd dynamically
(``exec {fd}<>``) and returns ``/dev/fd/$fd``.  The dedicated ``nc``
exits naturally at EOF; no file is written to B.

**Recursive relay (A → B → C):** B's ``rr_resolve`` triggers a
``RESOLVE`` toward A; A opens a tunnel through B to C.  Each level uses
its own dynamically allocated fds; no name collisions occur.

Intended use in a relay script running on B:

.. code-block:: bash

   #!/usr/bin/env bash
   source config/remote_run.sh          # fetched from A via the implicit source override
   rr_run "root@C" "$(rr_resolve deploy.sh)" --env production

rr_cleanup
~~~~~~~~~~

.. code-block:: text

   rr_cleanup -S <var>

Removes rr-managed variables from the named shared state object so the same
state variable can be reused safely by a later ``rr_init`` call.  Reserved for
future ControlMaster teardown as well.

``-S <var>``
    **Mandatory.**  Name of the state variable to strip.  As for ``rr_init``,
    omitting it, supplying it without a value, or supplying it twice is a
    structural call error rather than a silent no-op.

**Exit code**

+------------------------------------+-------------------------------------------+
| Constant                           | Condition                                 |
+====================================+===========================================+
| ``RR_ERR_MULTIPLE_STATE_INPUTS``   | ``-S`` supplied more than once            |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_STATE_VAR``       | ``-S`` absent                             |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_MISSING_ARGUMENT``        | ``-S`` supplied without a value           |
+------------------------------------+-------------------------------------------+
| ``RR_ERR_UNKNOWN_ARGUMENT``        | Unrecognised option in the option loop    |
+------------------------------------+-------------------------------------------+

Remote Script Categories
------------------------

Two categories of scripts may be executed via ``rr_run``:

**Category 1 — remote-run-aware scripts**
    The script explicitly sources ``config/remote_run.sh`` and uses the
    ``rr_*`` API.  It may call ``rr_run`` itself for nested remote execution,
    using ``rr_resolve`` to transfer scripts from the originating machine
    without writing to the relay filesystem.

**Category 2 — unaware scripts**
    The script has no knowledge of ``remote_run``.  It uses ``source`` as
    normal; the implicit ``source`` override intercepts these calls
    transparently.  No explicit ``rr_*`` calls are made.

Double Wrapper
--------------

Every file fetched via the ``source`` override is executed through a double
wrapper:

**Outer wrapper** (persistent for the duration of the ``source`` call):

1. Reads the **entire** file content from the protocol fd into a local
   variable; the dedicated ``nc`` sees EOF and terminates cleanly.
2. Calls the inner wrapper.
3. Executes cleanup after the inner wrapper returns — whether by normal
   completion or by ``return``.

Outer wrapper local variables are protected from ``eval`` inside the inner
wrapper by Bash scope rules.  ``handle_state`` is not used on the remote side.

**Inner wrapper** (one per sourced file):

- Executes ``eval "$content"`` as a **single block**, correctly handling
  multi-line constructs (function bodies, ``if/fi``, ``while/done``) and
  reproducing the parse-then-execute semantics of ``source``.

Note: ``exit`` destroys the entire shell stack immediately; the outer wrapper
cannot intercept it.  Documented as an accepted limitation.

``source`` Semantics
--------------------

+---------------------------------------------+----------+-----------------------------+
| Feature                                     | Status   | Notes                       |
+=============================================+==========+=============================+
| ``return`` in sourced file                  | Faithful | Outer wrapper recovers      |
+---------------------------------------------+----------+-----------------------------+
| ``$1``, ``$@``, ``$#``, ``shift``           | Faithful | Args forwarded to wrapper   |
+---------------------------------------------+----------+-----------------------------+
| Variables defined in sourced file           | Faithful | Same shell; no subshell     |
+---------------------------------------------+----------+-----------------------------+
| Functions defined in sourced file           | Faithful | Same shell; no subshell     |
+---------------------------------------------+----------+-----------------------------+
| Nested ``source``                           | Faithful | Recursive; same mechanism   |
+---------------------------------------------+----------+-----------------------------+
| ``local`` at file top level                 | Diverges | Becomes valid (see below)   |
+---------------------------------------------+----------+-----------------------------+
| ``BASH_SOURCE[0]`` accuracy                 | Approx.  | May show eval context       |
+---------------------------------------------+----------+-----------------------------+
| ``FUNCNAME`` / ``BASH_LINENO`` accuracy     | Approx.  | Wrapper frame may be visible|
+---------------------------------------------+----------+-----------------------------+
| Shell flags (``set -e``, ``set -x``, …)     | Faithful | Propagated from call site   |
+---------------------------------------------+----------+-----------------------------+

Limitations
-----------

- **No PTY is allocated.**  ``rr_run`` always uses ``ssh -T``.  Remote
  commands that require a controlling terminal (``sudo`` password prompts,
  ``read -s``, readline programs) will fail or behave unexpectedly.  Use
  key-based ``sudo NOPASSWD`` or pre-configure secrets before calling
  ``rr_run``.

- **``.`` (dot) is not overridden.**  Using ``.`` instead of ``source`` will
  attempt to read a file from the *remote* filesystem and will fail if the
  file is absent there.

- **Local CWD is fixed at invocation time.**  All paths given to ``source``
  are resolved relative to the local working directory at the time ``rr_run``
  is called, not relative to the currently executing script.

- **``local`` at the top level of a sourced file becomes valid.**  Under the
  wrapper function it is silently accepted.  This difference is benign for
  libraries that do not rely on this error.

- **``BASH_SOURCE[0]`` may not show the expected path.**  A parallel map is
  maintained for diagnostic use (visible in ``PS4`` output when ``set -x``
  is active).

- **``exit`` cannot be intercepted.**  A call to ``exit`` in the remote script
  or any sourced file terminates the entire remote shell immediately.

- **File descriptors opened with hard-coded numbers after library
  initialisation may collide.**  See :ref:`fd-allocation-rule` below.

- **Protocol channel limited to ~48 KB per file.**  Files larger than the OS
  socket buffer size require chunked transfers, which are not implemented.
  Realistic deployment scripts are well under this threshold.

.. _fd-allocation-rule:

File Descriptor Allocation Rule
--------------------------------

All libraries in this project allocate file descriptors **dynamically** using
the Bash auto-assignment form ``exec {var}<>``.  A library cannot protect
itself against application code that later opens a hard-coded fd number that
happens to coincide with a library-held fd.

**Applications must either:**

- Use dynamic fd allocation themselves (``exec {var}<>``), **or**
- Open all hard-coded fd numbers **before** sourcing any library from this
  project.

This rule applies to ``handle_state.sh``, ``remote_run.sh``, and all future
libraries that hold open file descriptors.

Security Model
--------------

The local file server enforces a **whitelist** of allowed paths:

- The default whitelist contains the directory of ``<script.sh>``.
- Additional entries are added with ``--allow`` (in ``rr_init`` or ``rr_run``).
- All requested paths are normalised (``realpath -m``) before checking.
- Requests for paths outside the whitelist receive an ``ERR`` response; the
  remote ``source`` call fails with exit code 1 and an error message on
  ``stderr``.
- Path traversal sequences (``..``) are handled by normalisation and do not
  bypass the whitelist.

The system is designed for executing *already-approved local scripts*, not for
sandboxing hostile code.

Error Codes
-----------

All public functions return 0 on success and a named constant on failure.
The constants are ``readonly`` globals available to callers after the library
is sourced.  Values 1–12 are reserved for ``handle_state.sh`` error codes
that may propagate via ``|| return $?``; no ``RR_ERR_*`` constant uses those
values unless the semantics are identical and confusion is impossible.

- ``RR_ERR_MULTIPLE_STATE_INPUTS=3``: ``-S`` was supplied more than once.  The
  call is rejected outright rather than letting the last occurrence win, which
  would silently write the state into a variable the caller is not watching.
  Aligned with ``HS_ERR_MULTIPLE_STATE_INPUTS``.
- ``RR_ERR_MISSING_STATE_VAR=7``: ``-S`` was required but not supplied.
  Aligned with ``HS_ERR_STATE_VAR_UNINITIALIZED``.
- ``RR_ERR_MISSING_ARGUMENT=8``: a required argument is absent — either a
  positional argument of ``rr_run``, or the value of an option such as ``-S``.
  Aligned with ``HS_ERR_MISSING_ARGUMENT`` and ``CG_ERR_MISSING_ARGUMENT``.
- ``RR_ERR_UNKNOWN_ARGUMENT=9``: an unrecognised token appeared in the
  option-parsing loop.  Not limited to dash-prefixed tokens.  Aligned with
  ``CG_ERR_SYNTAX_ERROR`` (pending rename to ``CG_ERR_UNKNOWN_ARGUMENT``).
- ``RR_ERR_PATH_RESOLUTION_FAILED=13``: ``realpath -m`` failed on an
  ``--allow`` path argument.
- ``RR_ERR_SCRIPT_NOT_FOUND=14``: the ``<script.sh>`` argument is not a
  readable file.
- ``RR_ERR_SSH_CONNECT_FAILED=15``: the ControlMaster SSH connection to the
  target host could not be established.
- ``RR_ERR_PORT_FORWARD_FAILED=16``: SSH ``-O forward`` failed to allocate a
  remote TCP port for the protocol channel.
- ``RR_ERR_FETCH_FAILED=17``: the remote bootstrap received an ``ERR``
  response to a ``GET`` request.  Set by ``_rr_outer_wrapper`` on the remote.
- ``RR_ERR_RESOLVE_FAILED=18``: the remote bootstrap received a
  non-``RESOLVE_OK`` response.  Set by ``_rr_do_resolve`` on the remote.
- ``RR_ERR_DEPENDENCY_MISSING=19``: a required tool (``nc``, ``ssh``,
  ``base64``, ``realpath``, ``mktemp``, ``dirname``, ``cat``, or ``sleep``)
  could not be resolved by ``guard`` at source time.  The library failed to
  load entirely; no ``rr_*`` functions are available.
- ``RR_ERR_MISSING_SCRIPT_ARGUMENT=20``: the ``<script.sh>`` positional
  argument of ``rr_run`` is absent.  Distinct from ``RR_ERR_MISSING_ARGUMENT``,
  which reports a missing ``<user@host>``.

Change History
--------------

.. list-table::
   :header-rows: 1
   :widths: 10 90

   * - PR
     - Summary
   * - #126
     - add Error Codes section; fix nc dependency note; fix exit-code table
   * - #TBD
     - -S mandatory for rr_init and rr_cleanup; per-function exit-code tables;
       document RR_ERR_MULTIPLE_STATE_INPUTS and RR_ERR_MISSING_SCRIPT_ARGUMENT
       [closes #120]
