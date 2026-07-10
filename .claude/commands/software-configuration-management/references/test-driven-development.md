# Test Driven Development

**Precondition**: Task 3 (Implementation Planning) completed with validated plan. Do not proceed without plan validation.

This task covers documentation updates and preliminary tests definition.

## Step 4: Documentation Updates
- **Objective**: Keep docs, comments, and AI skills aligned with the code.
- **Activities**:
  - Update README, Sphinx docs, skill files, or other relevant documentation.
  - Include usage notes, caveats, and cross-references as needed.
  - Commit the documentation changes.
- **Validation**: Documentation builds successfully (use `sphinx-docs` when applicable).

## Preliminary Tests Definition
- **Objective**: Define preliminary tests to illustrate the documented behavior.
- **Activities**:
  - Extend the relevant test suite (`test/...`), keeping new tests close to the projected behavior being implemented (focus on core tests that illustrate new or corrected behaviors, not edge cases).
  - Follow coding standards; use `xfail` tags for tests that are known to fail temporarily.
  - **Assert on captured stderr.** Whenever a bats test captures stderr (`run --separate-stderr`), assert its expected content: for an error/warning path, match the diagnostic (`[[ "$stderr" == *"..."* ]]`); for a clean/happy path, assert it is empty (`[[ -z "$stderr" ]]`). A captured stream that is never asserted is an untested output.
  - **Never silently delete a test.** When a change removes or replaces an existing test, either convert it in place or leave a `REVIEW PLACEHOLDER` comment mapping the old test title to the new test(s) that cover it (`old title -> new title`), so reviewers can see nothing was lost. These placeholders are cleaned up at integration (see `integration.md`).
  - Include clear commit messages referencing the issue.
  - When necessary, re-use helper modules such as `bats-support` or `bats-assert` from the `devel` branch.
  - Commit the extended test suite.
- **Validation**: Tests compile/run locally and reflect the intended behavior. New tests must fail at this step (use xfail if needed); a passing new test does not discriminate between old and new behaviors.
- **Note**: Confirm that the preliminary tests are a straightforward illustration of the documented behavior and correct if needed, then **stop**. Do not proceed to other tasks without approval on the documentation and the preliminary tests.