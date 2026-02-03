# Implementation Execution

This segment covers documentation, testing, implementation, and code review.

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