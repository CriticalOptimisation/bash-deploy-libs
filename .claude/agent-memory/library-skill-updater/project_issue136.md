---
name: issue-136 hs_extract_token and hs_write_token
description: Two zero-collision token routing helpers added to handle_state.sh in issue #136; document all three call forms
type: project
---

Issue #136 adds `hs_extract_token` and `hs_write_token` to `config/handle_state.sh` to eliminate the nameref collision surface identified in issue #104 (PR #109).

**Why:** Public entry points that accept `-S <statevar>` were using namerefs, which risk collision when a caller names their variable the same as a nameref local. The subshell-based `eval "$(...)"` pattern isolates the token extraction into a subprocess with zero collision surface.

**How to apply:** When writing or updating the handle-state library skill, document `hs_extract_token` with all three call forms (direct `--list-reserved`, normal eval, eval with `--list-reserved` splice) and `hs_write_token` with its two forms. Always show the canonical read-write and read-only entry-point patterns as the preferred approach for any public function accepting `-S`.

Key facts:
- `hs_extract_token` Form 2: `eval "$(hs_extract_token <local_name> "$@")"` — emits `local <local_name>='<value>'`
- `hs_extract_token` Form 3: `eval "$(hs_extract_token <local_name> --list-reserved "$@")"` — emits `local list_reserved=1` sentinel when `--list-reserved` detected
- `hs_write_token`: `eval "$(hs_write_token <source_local> "$@")"` — emits `<statevar>=<value>` (no `local`)
- Both helpers use `bash -c 'exit N'` to signal errors through eval
- `_hs_local_exists "$(local -p)" <name>` detects presence of sentinel locals
- OPTARG remains the only universally reserved name that cannot be used as an entry-point local
