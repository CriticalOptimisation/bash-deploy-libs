---
name: issue-136 hs_extract_token and hs_write_token
description: Two minimum-collision-surface token routing helpers added to handle_state.sh in issue #136; two call forms (direct and eval), eval form has two operational modes
type: project
---

Issue #136 adds `hs_extract_token` and `hs_write_token` to `config/handle_state.sh` to reduce the name-collision surface for public entry points identified in issue #104 (PR #109).

**Why:** Public entry points that accept `-S <statevar>` were using direct variable assignment via dynamic scoping, which risks collision when a caller names their variable the same as a local in the entry point. The subshell-based `eval "$(...)"` pattern isolates token access into a subprocess with a **minimal** (not zero) collision surface: `hs_extract_token` still declares `__hs_processed` and `__hs_remaining` in the subshell frame, but those are `__hs_`-prefixed and documented.

**How to apply:** When writing or updating the handle-state library skill, document `hs_extract_token` with its **two** call forms (direct `--list-reserved` and eval) and note that the eval form has two operational modes (normal and auto-`--list-reserved`). Document `hs_write_token` with its two forms (direct query and eval). Always show the canonical read-write and read-only entry-point patterns as the preferred approach for any public function accepting `-S`.

> **IMPORTANT:** Never call `_hs_*` or `__hs_*` internal functions from library code or documentation examples. Only call public API functions. Do not read the library source to infer behavior — rely solely on the documented public API.

Key facts:
- `hs_extract_token` has two call forms:
  - Form 1 (direct query): `hs_extract_token --list-reserved` — prints collision surface names
  - Form 2 (eval): `eval "$(hs_extract_token <local_name> "$@")"` — auto-detects `--list-reserved`
    at `$2` (when the caller passes it as their first arg); emits `local list_reserved=1` +
    `local <local_name>=''` in that mode, or `local <local_name>='<value>'` in normal mode
- `hs_write_token`: `eval "$(hs_write_token <source_local> "$@")"` — emits `<statevar>='<value>'` (no `local`)
- Both helpers use `bash -c 'exit N'` to signal errors through eval
- To detect if a variable is declared locally, use `local -p <name> >/dev/null 2>&1` (returns 0 if declared, 1 if not)
- OPTARG remains the only universally reserved name that cannot be used as an entry-point local
