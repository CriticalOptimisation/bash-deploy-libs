Remote Run Library
==================

Location
--------

- ``config/remote_run.sh``

Purpose
-------

This library provides a single entry point, ``remote_run``, which executes a
local shell script on a remote host via SSH **without writing any file to the
remote filesystem**.  The main script and every library it ``source``\s are
kept on the local machine; the remote side receives file content on demand
through a private TCP channel established by SSH port-forwarding.

The library is designed for scripts that are already validated locally and use
``source`` as their composition mechanism (e.g. ``handle_state.sh``,
``command_guard.sh``).

Dependencies
------------

+------------------+----------+-------------------------------------------+
| Dependency       | Side     | Notes                                     |
+==================+==========+===========================================+
| Bash ≥ 4.3       | Both     | Auto-assigned FDs; ``unset 'arr[-1]'``    |
+------------------+----------+-------------------------------------------+
| OpenSSH client   | Local    | ``ssh``, ``-tt``, ``-R`` required         |
+------------------+----------+-------------------------------------------+
| ``nc``           | Local    | Any variant supporting ``-l -p PORT``     |
+------------------+----------+-------------------------------------------+
| ``base64``       | Remote   | Standard on all major Linux distributions |
+------------------+----------+-------------------------------------------+

``nc`` availability is checked at startup.  If missing, ``remote_run`` prints
an installation hint and returns 1.

Architecture Overview
---------------------

Two independent channels are used:

**Protocol channel (TCP via SSH** ``-R``\ **)** — carries the program feed and
the file-serving protocol.  The local side starts a ``nc`` listener.  SSH
forwards a port on the remote to that listener.  The remote shell opens the
forwarded port as a bidirectional file descriptor.

**Interactive channel (PTY via SSH** ``-tt``\ **)** — standard SSH
pseudo-terminal.  Interactive commands (``read -p``, ``read -s``, readline
programs) use ``/dev/tty``, which resolves to the PTY slave.

::

    local nc server ◄── SSH -R tunnel ◄── remote bash fd (protocol)
      (GET / OK / ERR)

    local terminal ──► SSH -tt PTY ──► remote /dev/tty (interactive)

The remote bootstrap, delivered through the protocol channel, performs the
following steps before any user code runs:

1. Saves the protocol file descriptor (auto-assigned, ≥ 10).
2. Restores ``stdin``/``stdout``/``stderr`` to ``/dev/tty`` when a PTY is
   present.
3. Overrides ``source`` with a function that fetches file content on demand.
4. Wraps the main script in a numbered function and calls it.

Quick Start
-----------

.. code-block:: bash

   # Source the library once
   source "$(dirname "$0")/config/remote_run.sh"

   # Run a local script on a remote host
   remote_run user@host deploy.sh --env production

   # Allow an additional directory of libraries
   remote_run --allow /opt/shared/libs user@host deploy.sh

Inside ``deploy.sh`` or any script it sources, ``source`` works exactly as
locally:

.. code-block:: bash

   #!/usr/bin/env bash
   source config/handle_state.sh     # fetched from local machine on demand
   source config/command_guard.sh    # nested source — also fetched locally

   guard curl jq

   init_deployment() {
       local endpoint="$1"
       hs_echo "Deploying to $endpoint"
       # ... deployment logic ...
   }

   init_deployment "$1"

Public API
----------

remote_run
~~~~~~~~~~

.. code-block:: text

   remote_run [--allow <path>] [--ssh-opt <opt>] [--] <user@host> <script.sh> [args...]

Executes ``<script.sh>`` on ``<user@host>`` via SSH.  All ``source`` calls
inside the script resolve against the local filesystem.

**Parameters**

``--allow <path>``
    Permit access to ``<path>`` (file or directory) in addition to the default
    whitelist.  May be repeated.  Relative paths are resolved against the local
    working directory at invocation time.

``--ssh-opt <opt>``
    Pass an extra option to every ``ssh`` invocation (connection and port-
    forward setup).  May be repeated.  Useful for specifying a non-default
    identity file, port, or ``-o`` knobs:

    .. code-block:: bash

       remote_run --ssh-opt "-p 2222" \
                  --ssh-opt "-i ~/.ssh/deploy_key" \
                  --ssh-opt "-o StrictHostKeyChecking=no" \
                  user@host deploy.sh

``<user@host>``
    SSH target.  Any format accepted by ``ssh`` is valid (e.g. ``host``,
    ``user@host``, ``alias-from-ssh-config``).

``<script.sh>``
    Path to the local script to execute.  Resolved relative to the local
    working directory.

``[args...]``
    Positional arguments forwarded to the script as ``$1``, ``$2``, …

**Exit code**

Returns the exit code of the remote script, or one of the following local
error codes:

+------+---------------------------------------------------+
| Code | Meaning                                           |
+======+===================================================+
| 1    | Missing dependency (``nc``, ``ssh``)              |
+------+---------------------------------------------------+
| 1    | Script file not found or not readable             |
+------+---------------------------------------------------+
| 1    | SSH connection or port-forward setup failed       |
+------+---------------------------------------------------+

**Environment**

``remote_run`` does not modify the calling environment.  Temporary files are
not created.  The ``nc`` listener and background jobs are cleaned up when the
SSH session ends.

``source`` Semantics
--------------------

Inside the remote shell, ``source`` is overridden by a function that:

1. Sends a ``GET <path>`` request to the local file server.
2. Receives the file content encoded as a single-line base64 string.
3. Wraps the decoded content in a numbered Bash function (``__rr_wN``).
4. Calls the wrapper with any arguments passed to ``source``.

This approach faithfully reproduces the observable semantics of ``source`` for
the supported case (``source`` at the top level of a file):

+---------------------------------------------+----------+-----------------------------+
| Feature                                     | Status   | Notes                       |
+=============================================+==========+=============================+
| ``return`` in sourced file                  | Faithful | Wrapper is a function       |
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

Limitations
-----------

- **``source`` from a function body is not supported.**  Only ``source`` at
  the top level of a file (outside any function definition) is guaranteed to
  work.  Calling ``source`` from inside a function body may silently produce
  incorrect results.

- **``.`` (dot) is not overridden.**  Using ``.`` instead of ``source`` will
  attempt to read a file from the *remote* filesystem and will fail if the file
  is absent there.

- **Local CWD is fixed at invocation time.**  All paths given to ``source``
  are resolved relative to the local working directory at the time
  ``remote_run`` is called, not relative to the currently executing script.

- **``local`` at the top level of a sourced file becomes valid.**  In a real
  ``source`` at the top level this would be a syntax error.  Under the wrapper
  function it is silently accepted.  This difference is benign for libraries
  that do not rely on this error.

- **``BASH_SOURCE[0]`` may not show the expected path.**  The wrapper
  mechanism cannot set this variable to the remote path.  A parallel map
  ``__rr_source_map`` is maintained for diagnostic use.

- **Interactive I/O requires a foreground terminal.**  If ``remote_run`` is
  called from a background job or without a controlling terminal (CI, cron),
  SSH falls back to ``-T`` (no PTY).  Interactive commands will not have a
  terminal in that case.

- **Protocol channel limited to ~48 KB per file.**  Files larger than the OS
  socket buffer size require chunked transfers, which are not implemented.
  Realistic deployment scripts are well under this threshold.

Security Model
--------------

The local file server enforces a **whitelist** of allowed paths:

- The default whitelist contains the directory of ``<script.sh>``.
- Additional entries are added with ``--allow``.
- All requested paths are normalised (``realpath -m``) before checking.
- Requests for paths outside the whitelist receive an ``ERR`` response; the
  remote ``source`` call fails with exit code 1 and an error message on
  ``stderr``.
- Path traversal sequences (``..``) are handled by normalisation and do not
  bypass the whitelist.

The system is designed for executing *already-approved local scripts*, not for
sandboxing hostile code.
