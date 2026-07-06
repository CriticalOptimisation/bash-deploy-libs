#!/usr/bin/env bats

# Structural tests: verify change history sections are present in all
# files that require them (issue #43).
# Run with: bats test/test-file-structure.bats

setup_file() {
  bats_require_minimum_version 1.5.0
  export ROOT="$BATS_TEST_DIRNAME/.."
}

# ---------------------------------------------------------------------------
# Helper: last non-comment, non-blank line of a shell file
# ---------------------------------------------------------------------------
_last_code_line() {
  grep -v "^[[:space:]]*#" "$1" | grep -v "^[[:space:]]*$" | tail -1
}

# ---------------------------------------------------------------------------
# Library .sh files — must NOT end with "return 0"
#   Static analysis inlines sourced files (# shellcheck source=); a top-level
#   "return 0" at the end of the inlined content is treated as an unconditional
#   return in the calling file, making every subsequent definition unreachable
#   (SC2317).  The implicit exit-0 of the last function definition suffices.
# BATS test files — must end with "return 0" then a history block
#   (bats sources test files; explicit return 0 keeps source exit-clean)
# ---------------------------------------------------------------------------

# bats test_tags=structure,history,issue-43,issue-133
@test "config/command_guard.sh: last code line is NOT return 0" {
  [[ "$(_last_code_line "$ROOT/config/command_guard.sh")" != "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "config/command_guard.sh: change history block present" {
  grep -q "^# --- Change History" "$ROOT/config/command_guard.sh"
}

# bats test_tags=structure,history,issue-43,issue-133
@test "config/handle_state.sh: last code line is NOT return 0" {
  [[ "$(_last_code_line "$ROOT/config/handle_state.sh")" != "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "config/handle_state.sh: change history block present" {
  grep -q "^# --- Change History" "$ROOT/config/handle_state.sh"
}

# bats test_tags=structure,history,issue-133
@test "config/remote_run.sh: last code line is NOT return 0" {
  [[ "$(_last_code_line "$ROOT/config/remote_run.sh")" != "return 0" ]]
}

# bats test_tags=structure,history,issue-131,issue-133
@test "config/remote_run.sh: change history block present" {
  grep -q "^# --- Change History" "$ROOT/config/remote_run.sh"
}

# bats test_tags=structure,history,issue-43
@test "test/test-command_guard.bats: last code line is return 0" {
  [[ "$(_last_code_line "$ROOT/test/test-command_guard.bats")" == "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "test/test-command_guard.bats: change history block present" {
  grep -q "^# --- Change History" "$ROOT/test/test-command_guard.bats"
}

# bats test_tags=structure,history,issue-43
@test "test/test-hs_persist_state.bats: last code line is return 0" {
  [[ "$(_last_code_line "$ROOT/test/test-hs_persist_state.bats")" == "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "test/test-hs_persist_state.bats: change history block present" {
  grep -q "^# --- Change History" "$ROOT/test/test-hs_persist_state.bats"
}

# bats test_tags=structure,history,issue-131,issue-133
@test "test/test-remote_run.bats: last code line is return 0" {
  [[ "$(_last_code_line "$ROOT/test/test-remote_run.bats")" == "return 0" ]]
}

# bats test_tags=structure,history,issue-131,issue-133
@test "test/test-remote_run.bats: change history block present" {
  grep -q "^# --- Change History" "$ROOT/test/test-remote_run.bats"
}

# ---------------------------------------------------------------------------
# RST files — must contain an RST comment block with "Change History"
# ---------------------------------------------------------------------------

# bats test_tags=structure,history,issue-43
@test "docs/libraries/command_guard.rst: change history RST comment present" {
  grep -q "Change History" "$ROOT/docs/libraries/command_guard.rst"
}

# bats test_tags=structure,history,issue-43
@test "docs/libraries/handle_state.rst: change history RST comment present" {
  grep -q "Change History" "$ROOT/docs/libraries/handle_state.rst"
}

# bats test_tags=structure,history,issue-43
@test "docs/libraries/index.rst: change history RST comment present" {
  grep -q "Change History" "$ROOT/docs/libraries/index.rst"
}

# bats test_tags=structure,history,issue-131,issue-133
@test "docs/libraries/remote_run.rst: change history RST comment present" {
  grep -q "Change History" "$ROOT/docs/libraries/remote_run.rst"
}

# ---------------------------------------------------------------------------
# Skills directories — must each contain a history.md file
# ---------------------------------------------------------------------------


# bats test_tags=structure,history,issue-43
@test "software-configuration-management skill has history.md" {
  [[ -f "$ROOT/.claude/commands/software-configuration-management/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "handle-state skill has history.md" {
  [[ -f "$ROOT/.claude/commands/handle-state/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "bash-library-template skill has history.md" {
  [[ -f "$ROOT/.claude/commands/bash-library-template/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "bash-path-prefix-scan skill has history.md" {
  [[ -f "$ROOT/.claude/commands/bash-path-prefix-scan/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "github-issues skill has history.md" {
  [[ -f "$ROOT/.claude/commands/github-issues/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "sphinx-docs skill has history.md" {
  [[ -f "$ROOT/.claude/commands/sphinx-docs/history.md" ]]
}

# bats test_tags=structure,history,issue-131,issue-133
@test "remote-run skill has history.md" {
  [[ -f "$ROOT/.claude/commands/remote-run/history.md" ]]
}

# ---------------------------------------------------------------------------
# Claude skill files (.claude/commands/) — must be present for each library
# ---------------------------------------------------------------------------

# bats test_tags=structure,history,issue-131,issue-133
@test "remote-run Claude skill file present" {
  [[ -f "$ROOT/.claude/commands/remote-run.md" ]]
}

return 0

# --- Change History -------------------------------------------------------
# | PR    | Summary                                                        |
# |-------|----------------------------------------------------------------|
# | #43   | initial file — structural tests for PR change history sections |
# | #134  | invert return-0 assertions; add full remote_run coverage [closes #133] |
# | #142  | update history.md paths to .claude/commands/; remove skill-creator test [closes #141] |
