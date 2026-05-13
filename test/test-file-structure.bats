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
# Shell / BATS files — must end with "return 0" then a history block
# ---------------------------------------------------------------------------

SHELL_FILES=(
  config/command_guard.sh
  config/handle_state.sh
  test/test-command_guard.bats
  test/test-hs_persist_state.bats
)

# bats test_tags=structure,history,issue-43
@test "config/command_guard.sh: last code line is return 0" {
  [[ "$(_last_code_line "$ROOT/config/command_guard.sh")" == "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "config/command_guard.sh: change history block present" {
  grep -q "^# --- Change History" "$ROOT/config/command_guard.sh"
}

# bats test_tags=structure,history,issue-43
@test "config/handle_state.sh: last code line is return 0" {
  [[ "$(_last_code_line "$ROOT/config/handle_state.sh")" == "return 0" ]]
}

# bats test_tags=structure,history,issue-43
@test "config/handle_state.sh: change history block present" {
  grep -q "^# --- Change History" "$ROOT/config/handle_state.sh"
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

# ---------------------------------------------------------------------------
# Skills directories — must each contain a history.md file
# ---------------------------------------------------------------------------

SKILL_DIRS=(
  .github/skills/software-configuration-management
  .github/skills/handle-state
  .github/skills/bash-library-template
  .github/skills/bash-path-prefix-scan
  .github/skills/skill-creator
  .github/skills/github-issues
  .github/skills/sphinx-docs
)

# bats test_tags=structure,history,issue-43
@test "software-configuration-management skill has history.md" {
  [[ -f "$ROOT/.github/skills/software-configuration-management/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "handle-state skill has history.md" {
  [[ -f "$ROOT/.github/skills/handle-state/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "bash-library-template skill has history.md" {
  [[ -f "$ROOT/.github/skills/bash-library-template/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "bash-path-prefix-scan skill has history.md" {
  [[ -f "$ROOT/.github/skills/bash-path-prefix-scan/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "skill-creator skill has history.md" {
  [[ -f "$ROOT/.github/skills/skill-creator/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "github-issues skill has history.md" {
  [[ -f "$ROOT/.github/skills/github-issues/history.md" ]]
}

# bats test_tags=structure,history,issue-43
@test "sphinx-docs skill has history.md" {
  [[ -f "$ROOT/.github/skills/sphinx-docs/history.md" ]]
}
