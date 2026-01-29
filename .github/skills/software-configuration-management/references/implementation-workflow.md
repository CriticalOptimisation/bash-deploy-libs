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
- **Prohibition**: Even with formal approval, proceeding is prohibited if high-level show stoppers remain identified. The situation can only be resolved by a revised assessment (e.g., necessary fixtures have been implemented).

## Step 2: Branch Creation
- **Objective**: Create an isolated workspace for the approved work.
- **Activities**:
  - Create a feature branch from `main`/`master` following the naming convention `{type}/issue-{number}-{short-description}`, where {type} is:
    - `feature` for new features implemented in the `config` folder
    - `bug` for bugs (actual behavior different from documented or desirable behavior, or documentation error, or skill/process description error)
    - `test` for issues requiring additional tests, but failing tests must be labelled `bug` if they should pass and the error appears to be in the test rather than the library
    - `doc` for issues involving only documentation but not errors (e.g., translations, etc.)
  - Push the branch to the remote repository and ensure it is trackable.
- **Validation**: Branch exists, is pushed, and is clean relative to `main`.

## Step 3: Implementation Planning
- **Objective**: Turn the assessment into a practical plan.
- **Activities**:
  - Confirm the new branch is sane and references the approved issue.
  - Break down the work into specific tasks, identify files/components to change, and roughly describe their interactions.
  - Plan the testing strategy (unit/integration/manual) without repeating the high-level blocker list from Step 1 (since we assume no major blockers remain after Step 1 approval).
  - Update the issue with the plan and note any tooling or skill dependencies.
  - Review reviewer comments and consider their implications for the plan.
- **Validation**: The plan is recorded in the issue using markdown, and the branch and files are scoped accordingly.

## Step 4: Documentation Updates
- **Objective**: Keep docs, comments, and AI skills aligned with the code.
- **Activities**:
  - Update README, Sphinx docs, skill files, or other relevant documentation.
  - Include usage notes, caveats, and cross-references as needed.
  - Commit the documentation changes.
- **Validation**: Documentation builds successfully (use `sphinx-docs` when applicable).

## Step 5: Tests Development
- **Objective**: Drive the implementation with tests (where applicable).
- **Activities**:
  - Modify or add only the configuration items explicitly approved in the assessment.
  - Extend the relevant test suite (`test/...`), keeping new tests close to the projected behavior being implemented (focus on core tests that illustrate new or corrected behaviors, not edge cases).
  - Follow coding standards; use `xfail` tags for tests that are known to fail temporarily.
  - Include clear commit messages referencing the issue.
  - When necessary, re-use helper modules such as `bats-support` or `bats-assert` from the `devel` branch.
  - Commit the extended test suite.
- **Prohibitions**: Do not alter unrelated tests or scaffolding without explicit approval.
- **Validation**: Tests compile/run locally and reflect the intended behavior. New tests must fail at this step (use xfail if needed); a passing new test does not discriminate between old and new behaviors.

## Step 6: Functionality Implementation
- **Objective**: Ensure the approved change works as intended.
- **Activities**:
  - Apply the implementation changes following the approved design.
  - Match the existing coding style in the codebase. Minimize the size of code patches measured after discarding white space only changes (large blocks that are unchanged except for indentation, can increase the size of a patch, but do not make a large divergence in the logic itself).
  - Run all relevant unit and integration tests **locally** after implementation (CI is a backup, not a substitute).
  - Perform manual verification steps if required by the issue.
  - Commit the code before each validation attempt. It will be easier to manually repeat the tests, if needed, if the tested code matches a well-defined commit.
- **Validation**: Tests pass locally and test results are documented. CI is expected to mirror the local run.
- **Note**: Do not revisit the test design from Step 5 once Step 6 begins. Instead return to step 5 after human approval of an adequate justification if the core tests are wrong.

## Step 7: Code Review Request
- **Objective**: Surface the work for maintainers' review.
- **Activities**:
  - Open a PR with a descriptive title and body referencing the issue.
  - Assign the **maintainers team** as reviewers (@CriticalOptimisation/maintainers).
  - Link the original issue and summarize the changes.
  - Address review feedback iteratively.
- **Validation**: The pull request shows an approved review from a maintainer in GitHub (check the 'Reviews' tab; conversation resolution alone is insufficient).

## Step 8: Final Integration
- **Objective**: Let GitHub integrate the approved change after all protections pass.
- **Activities**:
  - Ensure CI/CD checks are green.
  - Confirm the PR satisfies branch protection requirements.
  - Allow GitHub to auto-merge once everything is ready (manual merging is not required). GitHub will squash all the commits in one.
  - Update dependent issues or TODOs if applicable.
  - After GitHub merges, synchronize the local repository.
  - If the PR addressed multiple issues, manually close any additional referenced issues after confirming tests pass (GitHub closes at most one issue per PR).
- **Validation**: The change merges automatically after meeting the protected branch checks, and local repo is synchronized.

## Step 9: Post-Implementation Validation
- **Objective**: Confirm the change stabilizes in the repository.
- **Activities**:
  - Monitor for regressions or failures triggered by the merge.
  - Update release notes or communication channels if required.
  - Archive or delete the feature branch if the work is complete (GitHub may have already deleted it).
- **Completion**: Issue is marked resolved and all follow-ups addressed.
- **Note**: GitHub will automatically close the associated issue and may delete the branch upon successful merge. The only remaining action is to synchronize the local repository.
