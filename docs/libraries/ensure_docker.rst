Ensure Docker Library
=====================

Location
--------

- ``config/ensure_docker.sh``

Purpose
-------

``ensure_docker.sh`` manages the Docker engine lifecycle on the local host:
detection, installation, uninstallation, and version-tracked cleanup.  It is
designed to be called via ``rr_run`` so the same operations can be applied
transparently to a remote host without any file being copied there.

The library is organised in two stages:

- **Stage 1** — atomic functions that have no side-effects on library state:
  ``ed_has_docker``, ``ed_install_docker``, ``ed_uninstall_docker``.
- **Stage 2** — state-managed functions that compose Stage 1 with
  ``handle_state.sh`` for idempotency and rollback:
  ``ed_ensure_docker``, ``ed_docker_version``, ``ed_cleanup``.

Dependencies
------------

+-------------------+---------------------------------+
| Dependency        | Notes                           |
+===================+=================================+
| ``command_guard.sh`` | Guarded at source time:      |
|                   | ``docker``, ``apt-get``,        |
|                   | ``apt-cache``, ``curl``, ``id`` |
+-------------------+---------------------------------+
| ``handle_state.sh`` | Stage 2 functions only.       |
|                   | Sourced automatically.          |
+-------------------+---------------------------------+
| Docker CE APT repo | Required by ``ed_install_docker``|
|                   | on Debian/Ubuntu hosts.         |
+-------------------+---------------------------------+
| Bash ≥ 4.3        | Nameref support in              |
|                   | ``handle_state.sh``.            |
+-------------------+---------------------------------+

All command-guard dependencies are verified at source time.  If any required
tool is absent the library fails to load and returns
``ED_ERR_DEPENDENCY_MISSING``.

Quick Start
-----------

.. code-block:: bash

   source "$(dirname "$0")/config/ensure_docker.sh"

   # Check Docker is present and satisfies a version constraint
   ed_has_docker ">=24.0.0" || { echo "Docker 24+ required"; exit 1; }

   # Install Docker if absent (requires root)
   ed_install_docker ">=24.0.0"

   # Idempotent: install only when needed, record action in state (Stage 2)
   local state=""
   ed_ensure_docker -S state ">=24.0.0" || return $?
   # ... use Docker ...
   ed_cleanup -S state   # restore the host to its prior state

Error Codes
-----------

- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: the caller does not have root
  privilege.  The library never escalates privileges on the caller's behalf.
- ``ED_ERR_MISSING_ARGUMENT=8``: a mandatory argument (typically ``-S``) was
  not supplied.
- ``ED_ERR_SYNTAX_ERROR=9``: an option or the version constraint string is
  malformed.
- ``ED_ERR_NO_DOCKER=13``: Docker is absent, unreachable, or not on
  ``PATH``.
- ``ED_ERR_NO_COMPOSE=14``: the Docker engine is present but the
  ``docker compose`` CLI plugin is missing.
- ``ED_ERR_WRONG_VERSION=15``: Docker is installed but does not satisfy
  the supplied version constraint.
- ``ED_ERR_VERSION_NOT_FOUND=16``: no APT candidate satisfies the
  requested version constraint.
- ``ED_ERR_VERSION_VULNERABLE=17``: *(reserved — CVE checking deferred to
  a future PR; currently never returned).*
- ``ED_ERR_DEPENDENCY_MISSING=19``: the library failed to load because a
  required tool or dependency library is absent.
- ``ED_ERR_ALREADY_INSTALLED=20``: ``ed_install_docker`` was called without
  ``--update`` and Docker is already installed.

Version Constraint Syntax
--------------------------

All entry points that accept ``[version_constraint]`` recognise the following
forms, where ``A``, ``B``, ``C`` are non-negative integers:

.. code-block:: text

   >=A.B.C            # at least A.B.C
   <D.E.F             # strictly below D.E.F
   >=A.B.C,<D.E.F     # range
   =A.B.C             # exact match
   =A.B               # equivalent to >=A.B.0,<A.(B+1).0

Public API — Stage 1
--------------------

ed_has_docker
~~~~~~~~~~~~~

``ed_has_docker [version_constraint]``

Checks whether a working Docker engine and Compose plugin are present and
optionally whether they satisfy a version constraint.  This function has no
side-effects and does not require root privilege.

Behaviour:

- Calls ``docker version``; on failure returns ``ED_ERR_NO_DOCKER``.
- Calls ``docker compose version``; on failure returns ``ED_ERR_NO_COMPOSE``.
- If ``version_constraint`` is given, parses it and compares the live engine
  version.  Returns ``ED_ERR_WRONG_VERSION`` when not satisfied.
- Returns ``0`` when Docker and Compose are present and any supplied
  constraint is met.

Errors:

- ``ED_ERR_NO_DOCKER=13``: Docker absent or unreachable.
- ``ED_ERR_NO_COMPOSE=14``: Compose plugin missing.
- ``ED_ERR_WRONG_VERSION=15``: constraint not satisfied.
- ``ED_ERR_SYNTAX_ERROR=9``: malformed constraint string.

ed_install_docker
~~~~~~~~~~~~~~~~~

``ed_install_docker [[--update] [version_constraint]]``

Installs Docker CE and the Compose plugin via the official APT repository.
This function is **not idempotent**: it fails with ``ED_ERR_ALREADY_INSTALLED``
when Docker is already present and ``--update`` is not set.  Use
``ed_ensure_docker`` when idempotency is required.

Options:

- ``--update``: upgrade an existing installation.  With ``--update`` and a
  constraint, the target version is the newest APT candidate satisfying the
  constraint.  A downgrade is performed when the target is older than the
  installed version.

Behaviour:

- Checks "already installed" before the privilege check: if Docker is present
  and ``--update`` is not set, returns ``ED_ERR_ALREADY_INSTALLED`` without
  requiring root.
- Verifies caller is root (``id -u == 0``); returns
  ``ED_ERR_INSUFFICIENT_PRIVILEGE`` otherwise.
- Idempotently adds the Docker CE APT repository and GPG key.
- Selects the newest APT candidate satisfying the constraint (or installs the
  latest stable release when no constraint is given).
- Installs ``docker-ce``, ``docker-ce-cli``, ``containerd.io``,
  ``docker-compose-plugin``.
- Polls ``/var/run/docker.sock`` (up to 30 s) before returning.
- Verifies the installation by calling ``ed_has_docker [constraint]``.

Errors:

- ``ED_ERR_ALREADY_INSTALLED=20``: Docker present and ``--update`` not set.
- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: not root.
- ``ED_ERR_VERSION_NOT_FOUND=16``: no APT candidate satisfies the constraint.
- ``ED_ERR_SYNTAX_ERROR=9``: malformed option or constraint.

ed_uninstall_docker
~~~~~~~~~~~~~~~~~~~

``ed_uninstall_docker``

Purges Docker CE, the CLI, containerd, and the Compose plugin via APT.
The call is idempotent: purging packages that are already absent exits 0.

Errors:

- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: not root.

Stage 2 State Variable Schema
-----------------------------

.. note::
   Stage 2 functions are not yet implemented.  Their API is documented here
   for planning purposes; they will be added in a subsequent PR.

Stage 2 functions persist state via ``handle_state.sh`` using three
associative arrays and one scalar.

``_ed_chain`` *(associative array)*
  Forward-linked list.  Each key is a git-commit hash (or the sentinel
  string ``"none"`` representing the pre-Docker state); each value is the
  git-commit hash of the *next* Docker installation.

  Example after two ``ed_ensure_docker`` calls:

  .. code-block:: text

     _ed_chain["none"]    = "abc1234"   # Docker was absent; installed abc1234
     _ed_chain["abc1234"] = "def5678"   # later updated to def5678
     _ed_chain["def5678"] = ""          # terminal node

``_ed_docker_ver`` *(associative array)*
  Maps each git-commit hash to the Docker engine semantic version string
  that was installed at that commit, e.g. ``_ed_docker_ver["abc1234"] = "24.0.7"``.

``_ed_compose_ver`` *(associative array)*
  Maps each git-commit hash to the Compose plugin semantic version string,
  e.g. ``_ed_compose_ver["abc1234"] = "2.20.0"``.

``_ed_head`` *(scalar)*
  The git-commit hash at the tip of ``_ed_chain`` (the currently installed
  Docker version), or ``"none"`` when Docker is not installed.

The action implied by any commit is determined from the chain structure
alone: a predecessor of ``"none"`` means the commit was the first
installation (reverting → uninstall); any other predecessor means it was
an update (reverting → downgrade to that predecessor's version via
``_ed_docker_ver``).

Public API — Stage 2
--------------------

ed_ensure_docker
~~~~~~~~~~~~~~~~

``ed_ensure_docker -S <state_var> [[--update] [version_constraint]]``

Idempotent wrapper around ``ed_has_docker`` and ``ed_install_docker``.
On success, appends the newly installed commit to ``_ed_chain``, records
its version data in ``_ed_docker_ver`` and ``_ed_compose_ver``, and
updates ``_ed_head``.  When Docker was already present and no action was
needed, ``_ed_head`` is set to the current commit and the chain gains one
entry (the current state) if it was previously empty.

ed_docker_version
~~~~~~~~~~~~~~~~~

``ed_docker_version -S <state_var> [-b] [-v] [-c]``

Returns version information about the currently installed Docker engine.
Reads ``_ed_head`` from state, then queries the live Docker process for
the requested fields.

- ``-b``: git-commit hash — ``docker version --format '{{.Server.GitCommit}}'``.
- ``-v``: engine semantic version — ``docker version --format '{{.Server.Version}}'``.
- ``-c``: Compose plugin version — ``docker compose version --short``.

No flags is equivalent to ``-b -v -c``; output order follows flag order.

ed_cleanup
~~~~~~~~~~

``ed_cleanup -S <state_var> [build_number]``

Reverses the last action recorded by ``ed_ensure_docker``.

If ``build_number`` is given it must be present in ``_ed_chain`` as a key;
otherwise ``ED_ERR_WRONG_VERSION`` is returned.

The revert algorithm traverses ``_ed_chain`` from ``"none"`` to find the
predecessor of ``_ed_head``:

- Predecessor is ``"none"`` → Docker was installed by this library;
  call ``ed_uninstall_docker``.
- Predecessor is a commit hash → Docker was updated; call
  ``ed_install_docker --update "$(_ed_docker_ver[$predecessor])"``
  to downgrade.

On success, removes ``_ed_head`` from the chain and version maps, and
updates ``_ed_head`` to the predecessor.

..

   Change History

   PR     Summary
   -----  ---------------------------------------------------------------
   #TBD   initial Stage 1 documentation (issue #132)
