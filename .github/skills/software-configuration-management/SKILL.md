---
name: software-configuration-management
description: Guide for software configuration management processes including issue tracking, branching strategies, testing workflows, and code review procedures. Use this skill when managing development processes, creating issues, branching for features, running tests, or conducting reviews. Triggers on requests like "create an issue", "start feature branch", "run tests", "review code", or any software development workflow task.
---

# Software Configuration Management

## Overview

This skill provides comprehensive guidance for managing software development processes using GitHub issues, branching strategies, automated testing, and code review workflows. It ensures consistent, traceable development practices that stabilize and professionalize software projects.

## Workflow Decision Tree

Choose the appropriate workflow based on your current development task:

### Issue Management
- **Creating Issues**: Use when reporting bugs, requesting features, or documenting tasks
- **Updating Issues**: Use when modifying existing issues (status, assignees, labels)
- **Issue Queries**: Use when searching or listing issues

### Branch Management  
- **Feature Branches**: Use when starting new development work
- **Branch Merging**: Use when integrating completed work
- **Branch Cleanup**: Use when removing obsolete branches

### Testing & Validation
- **Running Tests**: Use when validating code changes
- **Test Coverage**: Use when assessing test completeness
- **CI/CD Checks**: Use when verifying build status

### Code Review
- **Review Requests**: Use when requesting feedback on changes
- **Review Comments**: Use when providing feedback
- **Approval Process**: Use when finalizing merges

## Issue Handling

### Creating Issues

1. **Gather Context**
   - Repository information (owner/repo)
   - Issue type (bug, feature, task)
   - Clear title and description
   - Labels, assignees, milestones if applicable

2. **Use Templates**
   - Bug reports: Include steps to reproduce, expected vs actual behavior
   - Feature requests: Describe use case, acceptance criteria
   - Tasks: Break down into actionable items

3. **Execute Creation**
   - Call GitHub MCP tools to create the issue
   - Confirm creation with issue URL

### Updating Issues

- **Status Changes**: Open → In Progress → Resolved
- **Assignment**: Add/remove assignees
- **Labeling**: Apply appropriate labels (priority, type, component)
- **Comments**: Add progress updates or clarifications

## Branching Strategy

### Feature Branch Workflow

1. **Branch Creation**
   - Create from main/master branch
   - Use descriptive names: `feature/issue-123-add-login`
   - Push to remote repository

2. **Development**
   - Regular commits with clear messages
   - Reference issue numbers in commits
   - Keep branches focused on single features

3. **Integration**
   - Create pull request when ready
   - Request reviews from team members
   - Address review feedback

### Merge Process

- **Squash Merges**: For feature branches to keep history clean
- **Merge Commits**: For complex integrations
- **Fast-forward**: When appropriate for simple changes

## Testing Workflows

### Automated Testing

1. **Unit Tests**
   - Run after each significant change
   - Ensure all tests pass before commits

2. **Integration Tests**
   - Run on feature completion
   - Validate component interactions

3. **End-to-End Tests**
   - Run before merging to main
   - Ensure full system functionality

### Test Validation

- Use appropriate test runners (Jest, pytest, etc.)
- Check test coverage thresholds
- Review test results and fix failures

## Code Review Procedures

### Review Process

1. **Request Review**
   - Create pull request with clear description
   - Reference related issues
   - Assign appropriate reviewers

2. **Review Guidelines**
   - Check code quality and style
   - Verify tests are included
   - Ensure documentation is updated
   - Test changes locally if needed

3. **Approval & Merge**
   - Require minimum reviewer approvals
   - Address all blocking comments
   - Merge when ready

### Review Checklist

- [ ] Code follows project standards
- [ ] Tests are included and passing
- [ ] Documentation is updated
- [ ] Breaking changes are noted
- [ ] Performance impact assessed
- [ ] Security implications reviewed

## Resources

This skill includes example resource directories that demonstrate how to organize different types of bundled resources:

### scripts/
Executable code (Python/Bash/etc.) that can be run directly to perform specific operations.

**Examples from other skills:**
- PDF skill: `fill_fillable_fields.py`, `extract_form_field_info.py` - utilities for PDF manipulation
- DOCX skill: `document.py`, `utilities.py` - Python modules for document processing

**Appropriate for:** Python scripts, shell scripts, or any executable code that performs automation, data processing, or specific operations.

**Note:** Scripts may be executed without loading into context, but can still be read by Claude for patching or environment adjustments.

### references/
Documentation and reference material intended to be loaded into context to inform Claude's process and thinking.

**Examples from other skills:**
- Product management: `communication.md`, `context_building.md` - detailed workflow guides
- BigQuery: API reference documentation and query examples
- Finance: Schema documentation, company policies

**Appropriate for:** In-depth documentation, API references, database schemas, comprehensive guides, or any detailed information that Claude should reference while working.

### assets/
Files not intended to be loaded into context, but rather used within the output Claude produces.

**Examples from other skills:**
- Brand styling: PowerPoint template files (.pptx), logo files
- Frontend builder: HTML/React boilerplate project directories
- Typography: Font files (.ttf, .woff2)

**Appropriate for:** Templates, boilerplate code, document templates, images, icons, fonts, or any files meant to be copied or used in the final output.

---

**Any unneeded directories can be deleted.** Not every skill requires all three types of resources.
