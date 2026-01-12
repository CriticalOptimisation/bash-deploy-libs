# Copilot / Agent Instructions for PlexMediaServer ✅

## Quick summary
- Purpose: helpers and templates to deploy a Plex Media Server via Docker Compose (see `docker-compose-bridge.yml.template`).
- Key scripts live in `config/` and are small, well-documented, and meant to be sourced by installer scripts (not run as standalone daemons).

---

## Where to look (important files)
- `docker-compose-bridge.yml.template` — example compose file showing expected ports, volumes and env vars for Plex.
- `config/remote_access.sh` — reusable remote operations used by installer(s): DNS/ping checks, SSH access helpers, remote user management, preparing uploads from git, syncing files via tar over SSH, checking secrets, and remote `docker compose` validation.
- `config/handle_state.sh` — small helpers to persist local variables between functions (`hs_persist_state`).

---

## High-level architecture & intent 💡
- This repository provides *deployment helper scripts* rather than a full application. The main flow is:
  1. Prepare an upload (local working tree or a git ref) with `prepare_upload_from_git`.
  2. Sync files to a remote service account via `sync_files_to_remote` (tar pipe over SSH).
  3. Ensure secrets referenced in the compose file exist on the remote host (`ensure_secrets_on_remote`).
  4. Validate the remote `docker compose` configuration (`check_remote_docker_compose`).
- Preferred runtime on remote: Docker Engine + Docker Compose v2 (invoked as `docker compose`).

---

## Project-specific conventions & patterns 🔧
- Scripts are designed to be sourced and used by other scripts (`source config/remote_access.sh`), not as standalone CLI tools.
- **Explicit return codes**: functions do not rely on `set -e`. Each function returns explicit exit codes and prints clear human- and machine-friendly messages — callers must check return values.
- **Dependencies**: Tools expected on the developer machine: `git`, `yq` (used to inspect `docker-compose` secrets), `ssh`, `ssh-agent`, `getent` (or `nslookup`/`host`), `ping`, and `docker`/`docker compose` on the remote side.
- **Bash features**: Files use Bash features like `local -n` (name references) and `local -p`, so tests and CI should use a modern Bash interpreter (check compatibility with your target systems).
- **Secrets model**: Secrets are expected in a compose file under `secrets:` with a `file` attribute. The helper will attempt to upload those secret files when missing on the remote side.
- **Non-abort behavior**: Functions print informative messages and return non-zero on error rather than aborting with global traps — this makes them composable and easier to test.

---

## Concrete examples for agents (copyable) ✍️
- Source module and check connectivity:

```bash
source config/remote_access.sh
check_dns_and_ping "remote.example.com" || echo "dns/ping failed"
```

- Ensure SSH access (may prompt to use ssh-agent fallback):

```bash
ensure_ssh_access "remote.example.com" 2 || echo "ssh failed"
```

- Prepare upload from current tree (caller must clean up):

```bash
prepare_upload_from_git "current" UPLOAD_DIR && echo "Upload dir: $UPLOAD_DIR"
# after use
cleanup_temp_upload_dir "$UPLOAD_DIR"
```

- Validate secrets usage in `docker-compose.yml` (requires `yq`):

```bash
ensure_secrets_on_remote docker-compose.yml remote.example.com plex /home/plex || echo "secrets missing"
```

- Check remote docker-compose config:

```bash
check_remote_docker_compose remote.example.com plex /home/plex || echo "remote compose invalid"
```

---

## Things an agent should avoid or double-check ⚠️
- Do **not** assume functions abort on failure — always check return values explicitly.
- Avoid using `docker-compose` (v1) command variants; the scripts call `docker compose` (v2).
- When editing code, maintain the explicit return-code style and keep output machine- and human-friendly.
- If proposing new behaviors (e.g., adding `set -e`), validate how it affects callers and update all call sites.

---

## Questions / Notes for the maintainer ❓
- Are there any existing installer entrypoints (e.g., a `configure` script) you want referenced here? The `remote_access.sh` mentions a `configure` routine (from a related traefik project).
- Do you want a short automated test harness (simple shunit2/unit tests) to validate functions like `prepare_upload_from_git` and `ensure_secrets_on_remote`?

---

If you want, I can: add a small `README.md` summarizing usage, add a `scripts/test-smoke.sh` harness for quick local testing, or iterate the instruction file to add missing workflows — which would you prefer? ✅
