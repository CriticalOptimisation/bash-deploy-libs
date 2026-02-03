---
name: software-configuration-management
description: Guide for software configuration management processes. Use this skill for all software development workflow tasks, including issue management, branching, testing, reviewing, and implementing changes. Triggers on any request related to SCM processes, such as creating issues, starting branches, running tests, reviewing code, or updating code.
---

# Software Configuration Management

## Overview
This skill keeps the surface area small: it helps you decide whether you are managing a GitHub issue (creating, updating, triaging, or tagging) or actually implementing an approved change. The detailed nine-step implementation workflow lives in the companion reference file so the top-level document can stay focused on task selection and guardrails.

**Critical Rule: Never commit directly to the main branch.** All changes to git-tracked files, including .vscode configurations, must be developed on feature branches and merged via pull requests. Direct commits to main will fail on protected branches and violate the SCM process.

## Task Selection
1. **Meta-task path** – Use this skill (and the `github-issues` skill) for issue creation, triage, labeling, or other housekeeping that does _not_ touch git-managed configuration items. Keep the local clone synchronized with `origin/main`, maintain a read-only copy of `main` for reference, and avoid committing until an Issue Assessment is approved.
2. **Implementation path** – When a GitHub issue requires editing configuration files, trigger the segmented workflow. Mandatory supervision approvals are required between segments:

   - **Shared Issue Understanding** (Step 1): Issue Assessment & Approval – Identify blockers and obtain explicit reviewer approval before proceeding.

   - **Implementation Planning** (Steps 2-3): Branch Creation and Planning – Create branch and finalize plan, then validate before execution.

   - **Implementation Execution** (Steps 4-7): Documentation Updates, Tests Development, Functionality Implementation, and Code Review Request – Develop and prepare for review.

   - **Integration** (Steps 8-9): Final Integration and Post-Implementation Validation – Merge and validate.

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
Use the companion reference files for the full details, but keep this summary in mind whenever a GitHub issue transitions into actual configuration work. The workflow is divided into four segments with mandatory approvals between them.

- **Shared Issue Understanding** (Step 1): Issue Assessment & Approval – Identify blockers and obtain approval.
- **Implementation Planning** (Steps 2-3): Branch Creation and Planning – Set up workspace and finalize plan.
- **Implementation Execution** (Steps 4-7): Documentation, Testing, Implementation, and Review – Develop and review changes.
- **Integration** (Steps 8-9): Final Integration and Validation – Merge and confirm stability.

Each segment's details are in the respective reference files under [references/](references/).

Every implementation status update should cite the relevant assessment in the issue comments so reviewers understand that the change followed this documented process.

**Note**: Conversations in pull requests are resolved by the user (e.g., the maintainer), not by the implementer. The implementer provides summaries of changes made in response to each conversation, but does not mark them as resolved.
