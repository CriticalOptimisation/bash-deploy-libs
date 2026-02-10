# Implementation

**Precondition**: Task 4 (Test Driven Development) completed with approval on documentation and preliminary tests. Do not proceed without approval.

This task covers source code implementation, edge-cases tests expansion, testing, and prepare for review.

## Source Code Implementation
- **Objective**: Ensure the approved change works as intended.
- **Activities**:
  - Apply the implementation changes following the approved design.
  - Match the existing coding style in the codebase. Minimize the size of code patches measured after discarding white space only changes (large blocks that are unchanged except for indentation, can increase the size of a patch, but do not make a large divergence in the logic itself).
  - Run all relevant unit and integration tests **locally** after implementation (CI is a backup, not a substitute).
  - Perform manual verification steps if required by the issue.
  - Commit the code before each validation attempt. It will be easier to manually repeat the tests, if needed, if the tested code matches a well-defined commit.
- **Validation**: Tests pass locally and test results are documented. CI is expected to mirror the local run.
- **Note**: Do not revisit the test design from Task 4 once this begins. Instead return to Task 4 after human approval of an adequate justification if the core tests are wrong.

## Edge-cases Tests Expansion
- **Objective**: Expand tests to cover edge cases.
- **Activities**:
  - Add tests for edge cases based on the implementation.
  - Ensure all tests pass.
- **Validation**: All tests pass.

## Testing
- **Objective**: Validate the implementation.
- **Activities**:
  - Run the full test suite.
- **Validation**: All tests pass.

## Prepare for Review
- **Objective**: Surface the work for maintainers' review.
- **Activities**:
  - Open a PR with a descriptive title and body referencing the issue.
  - Assign the **maintainers team** as reviewers (@CriticalOptimisation/maintainers).
  - Link the original issue and summarize the changes.
  - Address review feedback iteratively.
- **Validation**: The pull request shows an approved review from a maintainer in GitHub (check the 'Reviews' tab; conversation resolution alone is insufficient).
- **Note**: Update the source code until the PR automated tests pass or until you discover an inconsistency in the tests. Ask permission to return to Task 4 if needed, and explain why you need to do that. Otherwise, follow the formal review process of the PR and make updates as directed by the maintainers.