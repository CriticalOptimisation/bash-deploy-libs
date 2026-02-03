# Implementation Planning

This segment covers branch creation and detailed planning.

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