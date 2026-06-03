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

- ``ED_ERR_CORRUPT_STATE=4``: the state token supplied via ``-S`` is not a
  valid ``handle_state.sh`` HS2 object.  Emitted by stateful entry points
  when state restoration fails at function entry.  The system is not touched.
  Aligned with ``HS_ERR_CORRUPT_STATE=4``.
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
- ``ED_ERR_HOST_INCOMPATIBLE=21``: the selected version exists in the APT
  repository but cannot be installed on this host (OS version mismatch,
  unsupported architecture, irresolvable package dependencies, or a
  container environment that lacks the required kernel capabilities).
  ``ed_install_docker`` emits a diagnostic that includes the ``apt-get``
  error output.  Callers that receive this code should consider a
  Docker-in-Docker deployment or a remote installation via ``rr_run``.

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
- ``ED_ERR_HOST_INCOMPATIBLE=21``: the selected version exists in APT but
  the ``apt-get install`` step fails due to host incompatibility (see
  diagnostic on stderr).  The caller should try DinD or a remote host.
- ``ED_ERR_SYNTAX_ERROR=9``: malformed option or constraint.

ed_uninstall_docker
~~~~~~~~~~~~~~~~~~~

``ed_uninstall_docker``

Purges Docker CE, the CLI, containerd, and the Compose plugin via APT.
The call is idempotent: purging packages that are already absent exits 0.

Errors:

- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: not root.

State Consistency Policy
------------------------

This policy applies to every stateful entry point
(``ed_ensure_docker``, ``ed_docker_version``, ``ed_cleanup``).

**Rule 1 — Full restoration at entry.**
The very first operation of every stateful entry point is restoring all
five state variables from the ``-S`` token.  No argument validation,
constraint checking, or system operation precedes this step.

**Rule 2 — Corrupt state is a hard failure.**
If restoration fails (invalid or corrupted HS2 token), the entry point
emits an ``[ERROR]`` message to stderr and returns
``ED_ERR_CORRUPT_STATE=4``.  Nothing is done to the system.

**Rule 3 — Single persist point on success.**
``hs_persist_state`` is called exactly once, at the successful exit of
the entry point, after all system operations have completed.  On any
failure path the function returns without calling ``hs_persist_state``,
leaving the state token identical to what was passed in.

Implementation pattern::

    local _new_state=""
    hs_persist_state -S _new_state -- chain node_commit node_cons \
        commit_ver commit_comp next_seq
    printf -v "$_state_var" '%s' "$_new_state"

``hs_persist_state`` writes into a fresh local (no prior state → no
collision possible).  The final ``printf -v`` copies the serialised token
into the caller's variable in a single Bash string assignment — atomic in
the Bash memory model.

**Consequence.**  On failure, the system is unchanged *and* the state
token is unchanged — there is nothing to undo.  On success, the state
token is updated atomically to reflect the completed operation.

**``ed_ensure_docker`` is not idempotent.**
Every **successful** call appends one new node to the chain and persists
the updated state, even when Docker was already present and no system
change was needed.  A failed call leaves state unchanged and adds no node.
Each caller owns exactly one node per successful call and must match it
with a single ``ed_cleanup`` call when the host is decommissioned.

Stage 2 State Variable Schema
------------------------------

.. note::
   Stage 2 functions are not yet implemented.  Their API is documented here
   for planning purposes; they will be added in a subsequent PR.

Stage 2 functions persist state via ``handle_state.sh``.  The five state
variables below have **fixed names**: every stateful entry point restores
them under exactly these names, and the accessor helpers rely on Bash's
dynamic scoping to read and write them without namerefs (see `Accessor
Helpers`_ below).

``chain`` *(associative array)*
  Forward-linked list where both keys and values are opaque sequence
  integers (or the sentinels ``"none"`` and ``"head"``).

  - ``chain["none"]`` is ``"head"`` in the initial empty state (no Docker
    installed by this library).
  - ``chain["none"] = "1"`` after the first installation; ``chain["1"] = "head"``
    marks it as the terminal node.
  - ``chain[N] = "head"`` always marks the current tip.

``node_commit`` *(associative array)*
  ``node_commit[seq]`` — git-commit hash of the Docker engine that was
  current when node *seq* was appended.

``node_cons`` *(associative array)*
  ``node_cons[seq]`` — version constraint string that was passed to the
  ``ed_ensure_docker`` call that created node *seq* (empty string if
  unconstrained).

``commit_ver`` *(associative array)*
  ``commit_ver[hash]`` — Docker engine semver for a given git-commit hash.
  Shared across nodes that reference the same commit.

``commit_comp`` *(associative array)*
  ``commit_comp[hash]`` — Compose plugin semver for a given git-commit hash.
  Shared across nodes that reference the same commit.

``next_seq`` *(scalar)*
  Monotonic integer counter; incremented each time a new node is appended.

Example after two ``ed_ensure_docker`` calls that install then update Docker:

.. code-block:: text

   chain["none"]  = "1"      chain["1"]  = "2"      chain["2"] = "head"
   node_commit["1"] = "abc"  node_commit["2"] = "def"
   node_cons["1"]   = ">=24.0.0"  node_cons["2"] = ">=24.0.5,<25.0.0"
   commit_ver["abc"]  = "24.0.7"  commit_ver["def"]  = "24.0.9"
   commit_comp["abc"] = "2.20.0"  commit_comp["def"] = "2.23.0"
   next_seq = 2

The action implied by cleanup is read from the chain: if the predecessor of
the terminal node is ``"none"``, Docker was installed by this library and
cleanup uninstalls it; otherwise cleanup downgrades to the predecessor's
``commit_ver``.  A new version must satisfy all ``node_cons`` values across
every node currently in the chain.

Accessor Helpers
----------------

.. note::
   Accessor helpers are not yet implemented.

Internal ``_ed_`` helper functions encapsulate all access to the five state
arrays.  They work without namerefs because Bash uses dynamic scoping:
``local`` variables declared in a stateful entry point are visible to every
helper it calls.  The convention is therefore:

1. Every stateful entry point restores the five state variables under their
   fixed names (``chain``, ``node_commit``, ``node_cons``, ``commit_ver``,
   ``commit_comp``, ``next_seq``) before calling any accessor.
2. Accessor helpers reference those names directly.  They must only be
   called from within a stateful entry point that has already restored state.

The accessor surface:

.. code-block:: bash

   # Chain (forward-pointer AA)
   _ed_chain_get  key            # → stdout: chain[key]
   _ed_chain_put  key value      # chain[key]=value
   _ed_chain_del  key            # unset chain[key]
   _ed_chain_pred target         # → stdout: key k where chain[k]==target
                                 #   (traverses from "none"; fails if not found)

   # Node record  (node_commit + node_cons)
   _ed_node_put    seq commit cons   # write both fields
   _ed_node_commit seq               # → stdout: node_commit[seq]
   _ed_node_cons   seq               # → stdout: node_cons[seq]
   _ed_node_del    seq               # unset both fields

   # Commit record  (commit_ver + commit_comp)
   _ed_commit_put     hash docker_ver compose_ver   # write both fields
   _ed_commit_docker  hash                          # → stdout: commit_ver[hash]
   _ed_commit_compose hash                          # → stdout: commit_comp[hash]
   _ed_commit_del     hash                          # unset both fields

   # Sequence counter
   _ed_seq_alloc      # increments next_seq; → stdout: new value

Public API — Stage 2
--------------------

ed_ensure_docker
~~~~~~~~~~~~~~~~

``ed_ensure_docker -S <state_var> [[--update] [version_constraint]]``

Restores state, then ensures Docker is present and satisfies the given
constraint, then appends one new node to the chain.  This function is
**not idempotent**: every **successful** call creates exactly one node,
even when Docker was already present and no system change was needed.
Each caller is responsible for issuing exactly one matching ``ed_cleanup``
call when the host is decommissioned.  A failed call never modifies state.

Behaviour:

1. Restore full state from ``-S`` token; return ``ED_ERR_CORRUPT_STATE``
   on failure.
2. Allocate a new sequence number via ``_ed_seq_alloc``.
3. Call ``ed_has_docker [version_constraint]``:

   - Returns ``0``: Docker present and satisfies constraint.  No system
     change; record current commit as the new node's commit.
   - Returns ``ED_ERR_NO_DOCKER``: call ``ed_install_docker [constraint]``.
   - Returns ``ED_ERR_WRONG_VERSION`` with ``--update``: call
     ``ed_install_docker --update [constraint]``.
   - Returns ``ED_ERR_WRONG_VERSION`` without ``--update``: propagate
     ``ED_ERR_WRONG_VERSION``; state unchanged.
   - Any other error: propagate; state unchanged.

4. Verify the new constraint is compatible with all existing ``node_cons``
   values.  If any conflict is detected: propagate ``ED_ERR_WRONG_VERSION``;
   state unchanged.
5. Write node (``_ed_node_put``, ``_ed_commit_put`` if commit is new).
6. Link the new node as the chain terminal (``_ed_chain_put``).
7. Persist state (``hs_persist_state``).

Errors:

- ``ED_ERR_CORRUPT_STATE=4``: state token invalid at function entry.
- ``ED_ERR_WRONG_VERSION=15``: no Docker version satisfies all constraints.
- ``ED_ERR_VERSION_NOT_FOUND=16``: no APT candidate satisfies the constraint.
- ``ED_ERR_HOST_INCOMPATIBLE=21``: version found but cannot be installed.
- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: install attempted but not root.
- ``ED_ERR_MISSING_ARGUMENT=8``: ``-S`` absent.
- ``ED_ERR_SYNTAX_ERROR=9``: malformed option or constraint.

ed_docker_version
~~~~~~~~~~~~~~~~~

``ed_docker_version -S <state_var> [-b] [-v] [-c]``

Restores state, then queries the live Docker process for the requested
version fields.

- ``-b``: git-commit hash — ``docker version --format '{{.Server.GitCommit}}'``.
- ``-v``: engine semantic version — ``docker version --format '{{.Server.Version}}'``.
- ``-c``: Compose plugin version — ``docker compose version --short``.

No flags is equivalent to ``-b -v -c``; output order follows flag order.
This function does not modify state; ``hs_persist_state`` is not called.

Errors:

- ``ED_ERR_CORRUPT_STATE=4``: state token invalid at function entry.
- ``ED_ERR_NO_DOCKER=13``: Docker unreachable.
- ``ED_ERR_NO_COMPOSE=14``: Compose plugin missing.
- ``ED_ERR_MISSING_ARGUMENT=8``: ``-S`` absent.
- ``ED_ERR_SYNTAX_ERROR=9``: unknown flag.

ed_cleanup
~~~~~~~~~~

``ed_cleanup -S <state_var> [build_number]``

Restores state, removes the terminal chain node, reverts the corresponding
system change if any, and persists the updated state.

If ``build_number`` is given it must equal ``node_commit[head_seq]``
(the commit recorded at the terminal node); otherwise returns
``ED_ERR_WRONG_VERSION``.

Revert algorithm:

1. Restore full state; return ``ED_ERR_CORRUPT_STATE`` on failure.
2. Identify the terminal node ``T`` (``chain[k] = "head"`` for some ``k``).
3. Find the predecessor ``P`` of ``T`` (``_ed_chain_pred "head"``).
4. Determine action from ``P``:

   - ``P == "none"`` and no remaining nodes after removal: Docker was
     installed by this library → call ``ed_uninstall_docker``.
   - ``P == "none"`` and nodes remain, or ``P`` is a seq number: check
     whether current Docker version satisfies all remaining
     ``node_cons`` values.  If not, call
     ``ed_install_docker --update "$(_ed_commit_docker "$(_ed_node_commit "$P")")"``
     to downgrade.  If yes, no system change.

5. Remove ``T`` from chain and node maps (``_ed_node_del``, ``_ed_chain_del``).
   Remove commit record only if no other node references the same commit.
6. Persist state.

Errors:

- ``ED_ERR_CORRUPT_STATE=4``: state token invalid at function entry.
- ``ED_ERR_WRONG_VERSION=15``: ``build_number`` does not match terminal node.
- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: uninstall/downgrade attempted but not root.
- ``ED_ERR_MISSING_ARGUMENT=8``: ``-S`` absent.

..

   Change History

   PR     Summary
   -----  ---------------------------------------------------------------
   #TBD   initial Stage 1 documentation (issue #132)
