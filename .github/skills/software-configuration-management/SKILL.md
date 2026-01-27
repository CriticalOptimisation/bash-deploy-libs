---
name: software-configuration-management
description: Guide for software configuration management processes including issue tracking, branching strategies, testing workflows, and code review procedures. Use this skill when managing development processes, creating issues, branching for features, running tests, or conducting reviews. Triggers on requests like "create an issue", "start feature branch", "run tests", "review code", "implement feature", "update code" or any software development workflow task.
---

# Software Configuration Management

## Overview
This skill keeps the surface area small: it helps you decide whether you are managing a GitHub issue (creating, updating, triaging, or tagging) or actually implementing an approved change. The detailed nine-step implementation workflow lives in the companion reference file so the top-level document can stay focused on task selection and guardrails.

## Task Selection
1. **Meta-task path** – Use this skill (and the `github-issues` skill) for issue creation, triage, labeling, or other housekeeping that does _not_ touch git-managed configuration items. Keep the local clone synchronized with `origin/main`, maintain a read-only copy of `main` for reference, and avoid committing until an Issue Assessment is approved.
2. **Implementation path** – When a GitHub issue requires editing configuration files, trigger the full nine-step workflow in [references/implementation-workflow.md](references/implementation-workflow.md). Step 1 (Issue Assessment & Approval) must be approved before editing files, Step 5 enforces running the planned local tests, and Step 7 requires assigning @CriticalOptimisation/maintainers and obtaining a maintainer review approval before merging.

## Meta-task Guidance
- Confirm you are operating on a clean baseline (`git fetch origin && git status`) before performing any meta-task so you do not misalign with remote `main`.
- Keep a separate read-only worktree that mirrors `main` for quick references and to prevent accidental commits on the protected branch. Use this dedicated procedure:
  ```
  git fetch origin
  git worktree remove ../repo-main  # if exists
  git worktree add ../repo-main main
  # Optionally: chmod -R a-w ../repo-main
  ```
  Worktrees can be stored under `.github/worktrees`. VS Code should recognize this worktree, allowing navigation to `main` for reference while keeping the main workspace on the feature branch.
- Route lightweight branch/tag housekeeping through this skill’s meta-task guidance; only enter the implementation path when configuration work is both scoped and approved.
## Issue Management Guidance
When handling issues (creation, updates, triage, labeling, or milestones), use the `github-issues` skill for execution, but follow SCM principles to ensure consistency and traceability:

1. **Determine action**: Decide if the task is issue creation, update, query, or other housekeeping.
2. **Gather context**: Review repo details, existing labels/milestones, and any related issues.
3. **Structure content**: Always use the custom templates from [references/templates.md](references/templates.md), which are tailored for this repository and override any generic templates in the `github-issues` skill.
4. **Execute**: Call the appropriate MCP tool or `gh` command via the `github-issues` skill.
5. **Confirm**: Verify the result on GitHub and ensure the action aligns with meta-task rules (e.g., no configuration changes without assessment approval).

For repo synchronization, worktree management, and distinguishing meta-tasks from implementation work, refer to the meta-task guidance above. This ensures issues are managed without risking unapproved changes to git-managed items.
## Implementation Workflow Summary
Use the companion reference file for the full details, but keep this summary in mind whenever a GitHub issue transitions into actual configuration work. Each numbered item below corresponds to the nine sequential steps in [references/implementation-workflow.md](references/implementation-workflow.md).

1. **Step 1 – Issue Assessment & Approval**: Identify blockers (missing infrastructure, SSH access, secrets, etc.), document the analysis in the issue, and obtain explicit reviewer approval before changing any files.
2. **Step 2 – Branch Creation**: Create a dedicated feature branch named `{type}/issue-{number}-{short-description}` off `main`, push it to the remote, and keep it tidy (clean status, no stray changes).
3. **Step 3 – Implementation Planning**: Scope the work, enumerate files/components to change, and sketch the testing strategy. Record this plan in the issue and reference any reviewer feedback.
4. **Step 4 – Documentation Updates**: Align docs, comments, and AI skills with the code. Use `sphinx-docs` when relevant to ensure documentation builds.
5. **Step 5 – Tests Development**: Drive the implementation with tests-first work: add or update tests under `test/` only, use shared helpers when needed, and keep coding standards high.
6. **Step 6 – Functionality Implementation**: Apply the approved code changes, execute the planned local unit/integration tests (CI is a backup), and record the results before moving on.
7. **Step 7 – Code Review Request**: Open a PR, link the issue, assign @CriticalOptimisation/maintainers, and require an actual maintainer review approval (not just conversation resolution).
8. **Step 8 – Final Integration**: Wait for the protected branch checks to pass and let GitHub merge automatically once all conditions are satisfied, then synchronize local repo and close any additional issues.
9. **Step 9 – Post-Implementation Validation**: Monitor for regressions, update release notes if needed, and archive the feature branch when the work is complete.

Every implementation status update should cite the relevant assessment in the issue comments so reviewers understand that the change followed this documented process.

**Note**: Conversations in pull requests are resolved by the user (e.g., the maintainer), not by the implementer. The implementer provides summaries of changes made in response to each conversation, but does not mark them as resolved.
