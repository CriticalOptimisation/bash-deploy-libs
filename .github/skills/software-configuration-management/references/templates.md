# Issue and PR Templates

**Note**: These templates are custom-tailored for this repository and always take precedence over any generic templates provided by the `github-issues` skill. Use these when creating or updating issues to ensure consistency with SCM workflows.

## Bug Report Template

```
## Bug Report

**Title:** [Bug] Brief description of the issue

**Description:**
Detailed description of the bug, including:
- What happened
- What should have happened
- Steps to reproduce
- Environment details

**Severity:** Critical/Major/Minor
**Priority:** High/Medium/Low

**Additional Context:**
- Screenshots
- Logs
- Related issues
```

## Feature Request Template

```
## Feature Request

**Title:** [Feature] Brief description of requested feature

**Problem Statement:**
What problem does this solve?

**Proposed Solution:**
Describe the proposed implementation

**Alternatives Considered:**
Other solutions that were considered

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3
```

## Pull Request Template

```
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Related Issues
Closes #123
Related to #456

## Checklist
- [ ] Code follows project standards
- [ ] Documentation updated
- [ ] Tests pass
- [ ] Reviewed by team member
```

### API Reference Example
- Overview
- Authentication
- Endpoints with examples
- Error codes
- Rate limits

### Workflow Guide Example
- Prerequisites
- Step-by-step instructions
- Common patterns
- Troubleshooting
- Best practices

## Change History Section Templates

Every file modified by a PR must carry a change history section. The format depends on the file type. Add one row per PR in ascending PR-number order. Use the GitHub API (`gh api repos/{owner}/{repo}/pulls/{n}/files`) to confirm which files a PR actually changed — do not rely on `git log`.

### Shell and BATS files (`.sh`, `.bats`)

Place after the last executable statement, before EOF. The `return 0` guards against accidental direct execution and marks the boundary between executable content and metadata.

```bash
return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #N     | one-line description                                          |
```

### RST documentation files (`.rst`)

Place at the end of the file. The `..` RST comment directive causes Sphinx to discard the block entirely; it never surfaces in built HTML or PDF output.

```rst
..

   Change History

   | PR     | Summary                                                       |
   |--------|---------------------------------------------------------------|
   | #N     | one-line description                                          |
```

### Skills `history.md` (SCM skill — tracks product→process causality)

A standalone file in the skill directory, **never referenced from skill content**. Records which product or process PRs drove each change to the skill files.

```markdown
# Change History

| PR  | Closes | Skill files changed | Process change |
|-----|--------|---------------------|----------------|
| #N  | #M     | filename.md         | one-line description |
```

### Skills `history.md` (all other skills)

```markdown
# Change History

| PR  | Closes | Summary |
|-----|--------|---------|
| #N  | #M     | one-line description |
```
