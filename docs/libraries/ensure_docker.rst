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

The library exposes two functional layers:

- **Layer 1** — stateless functions with no side-effects on library state:
  ``ed_has_docker``, ``ed_install_docker``, ``ed_uninstall_docker``.
- **Layer 2** — state-managed functions that compose Layer 1 with
  ``handle_state.sh`` for idempotency and rollback:
  ``ed_ensure_docker``, ``ed_docker_version``, ``ed_cleanup``.

Dependencies
------------

+------------------------+--------------------------------------------------+
| Dependency             | Notes                                            |
+========================+==================================================+
| ``command_guard.sh``   | Sourced at load time.  Guards the external       |
|                        | commands ``docker``, ``apt-get``, ``apt-cache``, |
|                        | ``curl``, ``id``.                                |
+------------------------+--------------------------------------------------+
| ``handle_state.sh``    | Layer 2 functions only.  Sourced automatically  |
|                        | by ``ensure_docker.sh``.                         |
+------------------------+--------------------------------------------------+
| Docker CE APT repo     | Required by ``ed_install_docker`` on             |
|                        | Debian/Ubuntu hosts.                             |
+------------------------+--------------------------------------------------+
| Bash ≥ 4.3             | Required by ``handle_state.sh``                  |
|                        | (nameref support).                               |
+------------------------+--------------------------------------------------+

All required external commands are verified at source time.  If any is
absent the library fails to load and returns ``ED_ERR_DEPENDENCY_MISSING``.

Quick Start
-----------

.. code-block:: bash

   source "$(dirname "$0")/config/ensure_docker.sh" || exit $?

   # Check whether Docker is present and satisfies a version constraint
   ed_has_docker ">=24.0.0" || { echo "Docker 24+ required" >&2; exit 1; }

   # Install Docker (requires root); fails if already installed without --update
   ed_install_docker ">=24.0.0" || exit $?

Layer 2 — commissioning and decommissioning with state tracking:

.. code-block:: bash

   source "$(dirname "$0")/config/ensure_docker.sh" || exit $?

   # Commission: ensure Docker is present and record what was done.
   # ed_ensure_docker appends one node to the state chain on every
   # successful call; each call must be matched by exactly one ed_cleanup.
   state=""
   ed_ensure_docker -S state ">=24.0.0" || exit $?

   # For long-lived servers the state string must be saved to permanent
   # storage (a file, a secrets manager, a configuration database keyed
   # by the server's unique identity) before the script exits.
   printf '%s\n' "$state" > /etc/ensure_docker.state

   # ... use Docker ...

   # Decommission: restore the host to its prior Docker state.
   state="$(< /etc/ensure_docker.state)"
   ed_cleanup -S state || exit $?
   rm -f /etc/ensure_docker.state

Error Codes
-----------

- ``ED_ERR_CORRUPT_STATE=4``: the state token supplied via ``-S`` is not a
  valid ``handle_state.sh`` HS2 object.  Emitted by stateful entry points
  when state restoration fails at function entry.  The system is not touched.
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
- ``ED_ERR_NO_SUITABLE_VERSION=16``: the APT repository contains no
  candidate that satisfies the requested version constraint.  The host is
  reachable and the repository is accessible; the constraint itself cannot
  be met with what is currently published.
- ``ED_ERR_VERSION_VULNERABLE=17``: *(reserved — CVE checking deferred to
  a future PR; currently never returned).*
- ``ED_ERR_DEPENDENCY_MISSING=19``: the library failed to load because a
  required external command or dependency library is absent.
- ``ED_ERR_ALREADY_INSTALLED=20``: ``ed_install_docker`` was called without
  ``--update`` and Docker is already installed.
- ``ED_ERR_HOST_INCOMPATIBLE=21``: a suitable version was found in the APT
  repository but ``apt-get install`` failed because the host cannot run it
  (OS version mismatch, unsupported CPU architecture, irresolvable package
  dependencies, or a container environment that lacks the required kernel
  capabilities).  ``ed_install_docker`` emits a diagnostic on stderr that
  includes the ``apt-get`` error output.  Callers that receive this code
  should consider a Docker-in-Docker deployment or a remote installation
  via ``rr_run``.

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

Public API — Layer 1
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
Without ``--update`` the function refuses to run when Docker is already
present, returning ``ED_ERR_ALREADY_INSTALLED``.  With ``--update`` the
function is idempotent: if the installed version already satisfies the
constraint it exits 0 without touching the system.

Options:

- ``--update``: allow installation onto a host that already has Docker.
  With a constraint, the target version is the newest APT candidate
  satisfying the constraint; a downgrade is performed when the target is
  older than the installed version.  Without a constraint, the latest
  stable release is targeted.

Behaviour:

- Checks "already installed" before the privilege check: if Docker is
  present and ``--update`` is not set, returns ``ED_ERR_ALREADY_INSTALLED``
  without requiring root.
- Verifies caller is root (``id -u == 0``); returns
  ``ED_ERR_INSUFFICIENT_PRIVILEGE`` otherwise.
- Idempotently adds the Docker CE APT repository and GPG key.
- Selects the newest APT candidate satisfying the constraint (or installs
  the latest stable release when no constraint is given).
- Installs ``docker-ce``, ``docker-ce-cli``, ``containerd.io``,
  ``docker-compose-plugin``.
- Polls the daemon socket (obtained from ``docker context inspect`` —
  honours custom ``DOCKER_HOST`` / context configuration) for up to 30 s
  before returning.
- Verifies the installation by calling ``ed_has_docker [constraint]``.

Errors:

- ``ED_ERR_ALREADY_INSTALLED=20``: Docker present and ``--update`` not set.
- ``ED_ERR_INSUFFICIENT_PRIVILEGE=7``: not root.
- ``ED_ERR_NO_SUITABLE_VERSION=16``: no APT candidate satisfies the constraint.
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

This policy applies to every Layer 2 entry point
(``ed_ensure_docker``, ``ed_docker_version``, ``ed_cleanup``).

**Rule 1 — Two-level structure: entry point and body helper.**
Every Layer 2 function is split into a thin API entry point and a body
helper (``_ed_<name>_body``).  The entry point does the minimum work
needed to extract the ``-S`` token variable name, then immediately copies
the token value into a local and delegates all further work to the helper:

.. code-block:: bash

    ed_ensure_docker() {
        # Option processing without getopts — extract -S <token_var> only
        local __ed_token_var=""
        # ... decode -S into __ed_token_var, validate it, return on error ...
        local __ed_state_token="${!__ed_token_var}"
        _ed_ensure_docker_body "$@" || return $?
        printf -v "$__ed_token_var" '%s' "$__ed_state_token"
    }

``${!__ed_token_var}`` is evaluated before ``__ed_state_token`` is
declared, so even if the caller named their variable ``__ed_state_token``
the indirection resolves correctly — ``__ed_state_token`` is not in the
nameref collision space.  Any local declared *before* that line would be
in the collision space, which is why the entry point declares nothing else.

The body helper accesses ``__ed_state_token`` via dynamic scoping.  It
restores the six state variables into its own frame, performs all
validation and system operations, and persists updated state back into
``__ed_state_token`` on success.  Because the state variables live in the
helper's frame, not the entry point's, they are never in the entry
point's collision space.  Within the helper, state variable names are not
prefixed; all other locals use a ``__ed_`` prefix.

**Rule 2 — Corrupt state is a hard failure.**
If state restoration fails (invalid or corrupted HS2 token), the body
helper emits an ``[ERROR]`` message to stderr and returns
``ED_ERR_CORRUPT_STATE=4``.  Nothing is done to the system.

**Rule 3 — Single persist point on success.**
``hs_persist_state`` is called exactly once per body helper, at the
successful exit path, after all system operations have completed.  On any
failure path the helper returns without calling ``hs_persist_state``,
leaving ``__ed_state_token`` (and therefore the caller's variable) unchanged.

.. code-block:: bash

    # Inside _ed_ensure_docker_body — persist on success only
    local __ed_new_state=""
    hs_persist_state -S __ed_new_state -- chain node_commit node_cons \
        commit_ver commit_comp next_seq || return $?
    __ed_state_token="$__ed_new_state"

``hs_persist_state`` writes into a fresh local (no prior state → no
collision possible).  Assigning back to ``__ed_state_token`` propagates
the result to the entry point, which writes it to the caller's variable
via ``printf -v``.

**Consequence.**  On failure, the system is unchanged *and* the caller's
state variable is unchanged — there is nothing to undo.  On success, the
caller's variable is updated atomically after all operations complete.

**``ed_ensure_docker`` is not idempotent.**
Every **successful** call appends one new node to the chain and persists
the updated state, even when Docker was already present and no system
change was needed.  A failed call leaves state unchanged and adds no node.
Each caller owns exactly one node per successful call and must match it
with a single ``ed_cleanup`` call when the host is decommissioned.

Layer 2 State Variable Schema
------------------------------

Layer 2 functions persist state via ``handle_state.sh``.  The six state
variables below have **fixed names**: every Layer 2 entry point restores
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

Internal ``_ed_`` helper functions encapsulate all access to the six state
arrays.  They work without namerefs because Bash uses dynamic scoping:
``local`` variables declared in a stateful entry point are visible to every
helper it calls.  The convention is therefore:

1. Every stateful entry point restores the five state variables under their
   fixed names (``chain``, ``node_commit``, ``node_cons``, ``commit_ver``,
   ``commit_comp``, ``next_seq``) before calling any accessor.
2. Accessor helpers reference those names directly.  They must only be
   called from within a stateful entry point that has already restored state.

The accessor surface:

Calling convention
  All five state arrays live in the caller's frame and are accessed
  directly by the helpers via Bash dynamic scoping — no parameter
  decoding needed for reads or writes.

  Getter helpers write their result into a **predefined output variable**
  whose name is part of the helper's calling convention (documented
  below).  Because calls are sequential, the caller saves the result into
  a local variable before the next getter call overwrites the output
  variable.  Mutators and deleters have no output variable.

.. code-block:: bash

   # Chain (forward-pointer AA)
   #   reads/writes chain[] directly via dynamic scoping
   #   getters write result into __ed_value (scalar)
   _ed_chain_get  key            # __ed_value = chain[key]
   _ed_chain_put  key value      # chain[key]=value
   _ed_chain_del  key            # unset chain[key]
   _ed_chain_pred target         # __ed_value = k where chain[k]==target
                                 #   (traverses from "none"; fails → return 1)

   # Node record  (node_commit + node_cons)
   #   reads/writes node_commit[] and node_cons[] via dynamic scoping
   #   getters write result into __ed_value (scalar)
   _ed_node_put    seq commit cons   # write both fields
   _ed_node_commit seq               # __ed_value = node_commit[seq]
   _ed_node_cons   seq               # __ed_value = node_cons[seq]
   _ed_node_del    seq               # unset both fields

   # Commit record  (commit_ver + commit_comp)
   #   reads/writes commit_ver[] and commit_comp[] via dynamic scoping
   #   getters write result into __ed_value (scalar)
   _ed_commit_put     hash docker_ver compose_ver   # write both fields
   _ed_commit_docker  hash                          # __ed_value = commit_ver[hash]
   _ed_commit_compose hash                          # __ed_value = commit_comp[hash]
   _ed_commit_del     hash                          # unset both fields

   # Sequence counter
   #   reads/writes next_seq via dynamic scoping
   #   writes result into __ed_seq (scalar)
   _ed_seq_alloc      # increments next_seq; __ed_seq = new value

Public API — Layer 2
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
- ``ED_ERR_NO_SUITABLE_VERSION=16``: no APT candidate satisfies the constraint.
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
     ``node_cons`` values.  If not, call ``_ed_node_commit "$P"`` (result
     in ``__ed_value``), then ``_ed_commit_docker "$__ed_value"`` (result
     in ``__ed_value``), then
     ``ed_install_docker --update "$__ed_value"`` to downgrade.
     If yes, no system change.

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
   #135   initial Stage 1 & 2 documentation (issue #132)
