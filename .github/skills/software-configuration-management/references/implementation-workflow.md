# Implementation Workflow

This companion document captures the detailed nine-step workflow referenced from the top-level skill guidance. Follow these steps sequentially whenever you are implementing an approved issue. The top-level skill keeps the decision tree, meta-task guidance, and important guardrails, while this file houses the step-by-step instructions for changes to source code, documentation, or AI skills.

## Step 1: Issue Assessment & Approval
- **Objective**: Establish a shared understanding of scope, dependencies, and blockers before editing any git-tracked files.
- **Activities**:
  - Review the issue description, comments, and attachments.
  - Assess technical impact, dependencies, and required configuration changes.
  - Identify **high-level show stoppers** that would prevent the task from progressing immediately (e.g., missing remote test infrastructure, unavailable SSH servers, or blocker secrets).
  - Document the analysis and proposed mitigation in the issue comments.
  - Ask for and obtain formal reviewer approval before touching any configuration controlled item.
- **Validation**: Approval comment or explicit sign-off is present in the GitHub issue conversation. No git changes until this approval exists.

## Step 2: Branch Creation
- **Objective**: Create an isolated workspace for the approved work.
- **Activities**:
  - Create a feature branch from `main`/`master` following the naming convention `feature/issue-{number}-{short-description}`.
  - Push the branch to the remote repository and ensure it is trackable.
- **Validation**: Branch exists, is pushed, and is clean relative to `main`.

## Step 3: Implementation Planning
- **Objective**: Turn the assessment into a practical plan.
- **Activities**:
  - Confirm the new branch is sane and references the approved issue.
  - Break down the work into specific tasks, identify files/components to change, and roughly describe their interactions.
  - Plan the testing strategy (unit/integration/manual) without repeating the high-level blocker list from Step 1.
  - Update the issue with the plan and note any tooling or skill dependencies.
  - Review reviewer comments and consider their implications for the plan.
- **Validation**: The plan is recorded in the issue, and the branch and files are scoped accordingly.

## Step 4: Tests Development
- **Objective**: Drive the implementation with tests (where applicable).
- **Activities**:
  - Modify or add only the configuration items explicitly approved in the assessment.
  - Extend the relevant test suite (`test/...`), keeping new tests close to the behavior being protected.
  - Follow coding standards; use `xfail` tags for tests that are known to fail temporarily.
  - Include clear commit messages referencing the issue.
  - When necessary, re-use helper modules such as `bats-support` or `bats-assert` from the `devel` branch.
- **Prohibitions**: Do not alter unrelated tests or scaffolding without explicit approval.
- **Validation**: Tests compile/run locally and reflect the intended behavior.

## Step 5: Functionality Implementation
- **Objective**: Ensure the approved change works as intended.
- **Activities**:
  - Apply the implementation changes following the approved design.
  - Run all relevant unit and integration tests **locally** after implementation (CI is a backup, not a substitute).
  - Perform manual verification steps if required by the issue.
  - Record the test results for review.
- **Validation**: Tests pass locally and test results are documented. CI is expected to mirror the local run.
- **Note**: Do not revisit the test design from Step 4 once Step 5 begins. Instead return to step 4 after human approval.

## Step 6: Documentation Updates
- **Objective**: Keep docs, comments, and AI skills aligned with the code.
- **Activities**:
  - Update README, Sphinx docs, skill files, or other relevant documentation.
  - Include usage notes, caveats, and cross-references as needed.
- **Validation**: Documentation builds successfully (use `sphinx-docs` when applicable).

## Step 7: Code Review Request
- **Objective**: Surface the work for maintainers' review.
- **Activities**:
  - Open a PR with a descriptive title and body referencing the issue.
  - Assign the **maintainers team** as reviewers (@CriticalOptimisation/maintainers).
  - Link the original issue and summarize the changes.
  - Address review feedback iteratively.
- **Validation**: Maintainers have been asked to review and any comments are resolved.

## Step 8: Final Integration
- **Objective**: Let GitHub integrate the approved change after all protections pass.
- **Activities**:
  - Ensure CI/CD checks are green.
  - Confirm the PR satisfies branch protection requirements.
  - Allow GitHub to auto-merge once everything is ready (manual merging is not required).
  - Update dependent issues or TODOs if applicable.
- **Validation**: The change merges automatically after meeting the protected branch checks.

## Step 9: Post-Implementation Validation
- **Objective**: Confirm the change stabilizes in the repository.
- **Activities**:
  - Monitor for regressions or failures triggered by the merge.
  - Update release notes or communication channels if required.
  - Archive or delete the feature branch if the work is complete.
  - Since merging takes place on GitHub, fully synchronize the local Git repository.
- **Completion**: Issue is marked resolved and all follow-ups addressed.
