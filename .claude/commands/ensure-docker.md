---
description: Guide for using the ensure_docker.sh library to detect, install, and manage the Docker engine lifecycle on local or remote hosts. Triggers when the task involves checking Docker presence, installing Docker via APT, uninstalling Docker, or managing Docker version constraints and rollback.
---

# Ensure Docker Library Skill

## When to Use

Use `ensure_docker.sh` when you need to:
- Check whether Docker (engine + Compose plugin) is present and meets a
  version constraint — `ed_has_docker`.
- Install or upgrade Docker on a host (Debian/Ubuntu) — `ed_install_docker`.
- Uninstall Docker entirely — `ed_uninstall_docker`.
- Idempotently ensure Docker is available and track the change for later
  rollback — `ed_ensure_docker` (Stage 2).

The library can be called locally **or** wrapped inside `rr_run` to operate
on a remote host without copying any file there.

Do **not** use this library when:
- The host is not Debian/Ubuntu (APT-based); the snap/rpm paths are out of
  scope for Stage 1.
- You need Docker for image builds or container management — use `ds_build_image`
  from `docker_service.sh` (#128) instead.

## Core Reference

`docs/libraries/ensure_docker.rst` — full API documentation.
`config/ensure_docker.sh` — implementation.

## Version Constraint Syntax

```
>=A.B.C,<D.E.F    range
>=A.B.C            lower bound
<D.E.F             upper bound
=A.B.C             exact match
=A.B               equivalent to >=A.B.0,<A.(B+1).0
```

## Error Codes

| Code | Name | Meaning |
|-----:|------|---------|
| 7  | `ED_ERR_INSUFFICIENT_PRIVILEGE` | Not root |
| 8  | `ED_ERR_MISSING_ARGUMENT` | Mandatory `-S` missing |
| 9  | `ED_ERR_SYNTAX_ERROR` | Bad option or malformed constraint |
| 13 | `ED_ERR_NO_DOCKER` | Docker absent or unreachable |
| 14 | `ED_ERR_NO_COMPOSE` | Compose plugin missing |
| 15 | `ED_ERR_WRONG_VERSION` | Constraint not satisfied |
| 16 | `ED_ERR_VERSION_NOT_FOUND` | No APT candidate matches constraint |
| 19 | `ED_ERR_DEPENDENCY_MISSING` | Library failed to load |
| 20 | `ED_ERR_ALREADY_INSTALLED` | Docker present; `--update` not set |

## Dependencies

| Module | Role |
|--------|------|
| `command_guard.sh` | Guarded commands: `docker`, `apt-get`, `apt-cache`, `curl`, `id` |
| `handle_state.sh` | Stage 2 state management only |

## Key Constraints

- The library **never escalates privileges**; callers must already be root
  when calling `ed_install_docker` or `ed_uninstall_docker`.
- `ed_install_docker` is **not idempotent** — use `ed_ensure_docker` when
  idempotency is required.
- CVE-based version selection is reserved for a future PR; the current
  implementation always selects the newest APT candidate satisfying the
  constraint.
