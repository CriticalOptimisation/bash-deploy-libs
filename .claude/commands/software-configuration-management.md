---
description: Guide for software configuration management processes. Use this skill for all software development workflow tasks, including issue management, branching, testing, reviewing, and implementing changes. Triggers on any request related to SCM processes, such as creating issues, starting branches, running tests, reviewing code, or updating code.
---

# Software Configuration Management

## Overview

This skill keeps the surface area small: it helps you decide whether you are managing a GitHub issue (creating, updating, triaging, or tagging) or actually implementing an approved change. The detailed nine-step implementation workflow lives in the companion reference file so the top-level document can stay focused on task selection and guardrails.

**Critical Rule: Never commit directly to the main branch.** All changes to git-tracked files, including .vscode configurations, must be developed on feature branches and merged via pull requests. Direct commits to main will fail on protected branches and violate the SCM process.

## Task Selection

1. **Meta-task path** – Use this skill (and the `github-issues` skill) for issue creation, triage, labeling, or other housekeeping that does _not_ touch git-managed configuration items. Keep the local clone synchronized with `origin/main`, maintain a read-only copy of `main` for reference, and avoid committing until an Issue Assessment is approved.
2. **Shared Issue Understanding** – Trigger this task when a GitHub issue is identified for implementation. Precondition: Issue exists and is assigned. Perform Step 1 (Issue Assessment & Approval) to identify blockers and obtain explicit reviewer approval. Do not proceed to other tasks without approval. Request clarification if the approval seems dubious or ambiguous.
3. **Implementation Planning** – Trigger this task on an issue after approval in Task 2. Precondition: Task 2 completed with approval. Perform Branch Creation and Detailed Planning to set up workspace and finalize plan. Do not proceed to other tasks without approval of the detailed plan.
4. **Test Driven Development** – Trigger this task after detailed plan validation in Task 3. Precondition: Task 3 completed with validated plan. Perform Documentation, Preliminary Tests Definition steps, then confirm that the documentation builds properly and is in strict adherence to the detailed plan. Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed, then **stop**. Do not proceed without approval on the documentation and the preliminary tests.
5. **Implementation** – Trigger this task after documentation and preliminary tests in Task 4 have been approved. Perform Source code Implementation, Edge-cases Tests Expansion, Testing, and Prepare for Review steps **in that order**. Finally, create the PR, and update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. Ask permission to return to step 4 if needed. Follow the formal review process of the PR and make updates as directed by the maintainers.
6. **Integration** – Trigger this task after review approval in Task 5. Precondition: Task 5 completed with maintainer review approval. Perform Final Integration and Validation until GitHub automatically merges the branch into `main` and deletes the remote branch. Evaluate new commits to main that must be integrated via rebase, final testing using the whole test suite, checking the tests status on the GitHub PR, local repository resynchronization after the merge (squash and merge). All edits must be minimal and justified at this stage.

## Meta-task Guidance

- Confirm you are operating on a clean baseline (`git fetch origin && git status`) before performing any meta-task.
- Keep a separate read-only worktree that mirrors `main` for quick references:
  ```
  git fetch origin
  git worktree remove ../repo-main  # if exists
  git worktree add ../repo-main main
  ```
  Worktrees can be stored under `.github/worktrees`.
- Route lightweight branch/tag housekeeping through this skill's meta-task guidance; only enter the implementation path when configuration work is both scoped and approved.

## Issue Management Guidance

When handling issues, use the `github-issues` skill for execution but follow SCM principles:

1. **Determine action**: Decide if the task is issue creation, update, query, or other housekeeping.
2. **Gather context**: Review repo details, existing labels/milestones, and any related issues.
3. **Structure content**: Always use the custom templates from `.github/skills/software-configuration-management/references/templates.md`, which are tailored for this repository and override any generic templates in the `github-issues` skill.
4. **Execute**: Call the appropriate MCP tool or `gh` command via the `github-issues` skill.
5. **Confirm**: Verify the result on GitHub and ensure the action aligns with meta-task rules.

## Implementation Workflow Summary

Companion reference files under `.github/skills/software-configuration-management/references/` contain full details:

- `shared-issue-understanding.md` — Task 2: Issue Assessment & Approval
- `implementation-planning.md` — Task 3: Branch Creation and Planning
- `test-driven-development.md` — Task 4: Documentation and Preliminary Tests
- `implementation.md` — Task 5: Source Code, Edge-cases, Testing, and PR
- `implementation-workflow.md` — full nine-step workflow overview
- `implementation-execution.md` — Task 5 & 6 execution details
- `integration.md` — Task 6: Final Integration and Validation

Every implementation status update should cite the relevant assessment in the issue comments so reviewers understand that the change followed this documented process.

**Note**: Conversations in pull requests are resolved by the maintainer, not by the implementer. The implementer provides summaries of changes made in response to each conversation but does not mark them as resolved.
