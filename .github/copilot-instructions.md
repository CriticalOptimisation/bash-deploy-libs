# Copilot / Agent Instructions for PlexMediaServer ✅

## Quick summary
- Purpose: helpers and templates to deploy a Plex Media Server via Docker Compose (see `docker-compose-bridge.yml.template`).
- Key scripts live in `config/` and are small, well-documented, and meant to be sourced by installer scripts (not run as standalone daemons).

---

## Where to look (important files)
- `.github/skills/software-configuration-management/SKILL.md` — the software configuration management skill.
- `config/*.sh` — reusable libraries.
- `docs/libraries/` — human-readable documentation for each library script.
- `test/` — Bats tests for the libraries.

---

## High-level architecture & intent 💡
- This repository provides *deployment helper scripts* rather than a full application.
- `PlexMediaServer installer` is an application example rather than a core part of the repository.
- The project is driven by documentation updates, followed by tests updates matching the newly documented behaviours, and finally code updates to make the tests pass.
- Human-readable documentation is provided in `docs/` alongside the code, with the intent that AI agents write it for humans.
- AI agents should use the preferred usage patterns described in the dedicated, per-library skills, rather than try to infer usage from the code and the documentation alone.
- AI agents must create issues in GitHub unforeseen difficulty they encounter, and must describe how they worked around the problem or what additional information is needed.
- Skills and documentatio are git-tracked items that must go through the established SCM process for any change.

---

## Project-specific conventions & patterns 🔧
- **Strong process model**: Always follow the established software configuration management (SCM) process described in the associated skill.
- Scripts under config are designed to be sourced and used by other scripts (`source config/handle_state.sh`), not as standalone CLI tools.
- **Explicit return codes**: functions do not rely on `set -e`. Each function returns explicit exit codes and prints clear human- and machine-friendly messages — callers must check return values.
- **Bash features**: Files use Bash features like `local -n` (name references) and `local -p`, so tests and CI should use a modern Bash interpreter (check compatibility with your target systems).
- **Secrets model**: Secrets are expected in a compose file under `secrets:` with a `file` attribute. The helper will attempt to upload those secret files when missing on the remote side.
- **Non-abort behavior**: Functions print informative messages and return non-zero on error rather than aborting with global traps — this makes them composable and easier to test.
- **Library skills**: Each library script (e.g., "config/handle_state.sh") is associated
with a corresponding skill teaching AI agents how to use it, in parallel with documentation
intended for humans. These skills can be found in `.github/skills/`.

---

## Things an agent should avoid or double-check ⚠️
- **Never** make change to any git-tracked file without going through the established SCM process (exception: .vscode folder for local settings).
- Do **not** assume functions abort on failure — always check return values explicitly.
- Do **not** use `docker-compose` (v1) command variants; the scripts call `docker compose` (v2).
- Double-check that a detailed assessment of the work is available in the GitHub issue's discussion **before** makeing any change to a git-tracked item.
- Create new issues for deferred work rather than overextending the scope of the current task.
- Run the tests before each commit and ensure that tests that are supposed to fail do fail and tests that are supposed to pass do pass.

