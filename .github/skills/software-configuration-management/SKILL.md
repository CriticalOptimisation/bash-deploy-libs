---
name: software-configuration-management
description: Guide for software configuration management processes including issue tracking, branching strategies, testing workflows, and code review procedures. Use this skill when managing development processes, creating issues, branching for features, running tests, or conducting reviews. Triggers on requests like "create an issue", "start feature branch", "run tests", "review code", "implement feature", "update code" or any software development workflow task.
---

# Software Configuration Management

## Overview

This skill provides comprehensive guidance for managing software development processes using GitHub issues, branching strategies, automated testing, and code review workflows. It ensures consistent, traceable development practices that stabilize and professionalize software projects.

## Task-Based Structure

The skill operates in two primary modes based on whether the task involves a new issue or implementing an existing issue.

### Decision Tree: New Issue vs Existing Issue

1. **Is this task related to an existing GitHub issue?**
   - Yes → Proceed to **Implementing an Existing Issue** (9-step sequential process)
   - No → Proceed to **Issue Management** (create/update/query issues)

**CRITICAL PROHIBITION**: It is strictly forbidden to modify any git-managed configuration item (source code, documentation, configuration files, etc.) without an approved assessment for an existing GitHub issue. Any request to make changes must be reformulated as issue-related tasks.

## Issue Management (New Issues)

When dealing with new issues, use these tools:

### Creating Issues
- Report bugs, vulnerabilities, or request features
- Document tasks and improvements
- Use structured templates for consistency

### Updating Issues
- Modify status, assignees, labels
- Add comments and progress updates

### Querying Issues
- Search and list repository issues
- Analyze issue patterns and priorities

### Issue Assessment
- Evaluate issue impact and scope
- Seek formal approval for implementation assessments

## Implementing an Existing Issue (9-Step Sequential Process)

When implementing an existing GitHub issue, follow these nine mandatory steps in sequence. Each step requires completion before proceeding to the next.

### Step 1: Issue Assessment & Approval
- **Objective**: Establish shared understanding of the issue
- **Activities**:
  - Review issue description, comments, and attachments
  - Assess technical impact and dependencies
  - Identify required changes to configuration items
  - Document assessment in issue comments
- **Approval Required**: Assessment must be formally approved by a reviewer before proceeding
- **Prohibition**: No changes to any configuration items until assessment is approved
- **Validation**: Formal approval in GitHub issue conversation.

### Step 2: Branch Creation
- **Objective**: Create isolated development environment
- **Activities**:
  - Create feature branch from main/master
  - Use naming convention: `feature/issue-{number}-{description}`
  - Push branch to remote repository
- **Validation**: Branch exists and is properly named

### Step 3: Implementation Planning
- **Objective**: Plan the technical solution
- **Activities**:
  - Check that the new branch is sane, especially that tests pass
  - Break down assessment into specific tasks
  - Identify files and components to modify
  - Plan testing strategy
  - Update issue with implementation plan
  - Review comments left by reviewers in the GitHub issue
- **Constraint**: Only plan changes within approved assessment scope
- **Important**: Comprehensive plan must cover program code, documentation, tests and skills.
- **Validation**: The branch is sane and the plan is comprehensive.
- **Fallback**: Create related issues in GitHub if step validation fails.

### Step 4: Tests Development
- **Objective**: Implement the approved changes using a tests-first approach
- **Activities**:
  - Modify or create only configuration items specified in assessment
  - Extend the test suite only: no change out of the `test` folder
  - Follow coding standards and best practices. Use xfail tag on new tests.
  - Commit changes with clear messages referencing the issue
  - If relevant, cherry-pick the submodules bats-support and/or bats-assert from the `devel` branch, and use them to write new more readable bats tests
- **Prohibition**: Never change an existing test, stub, scaffolding or fixture unless that is the explicit focus of the issue.
- **Prohibition**: No changes outside assessment scope without renewed approval
- **Validation**: Old tests must pass unless the issue deals specifically with failing tests, new tests must fail, if any.

### Step 5: Functionality Implementation
- **Objective**: Validate changes work correctly
- **Activities**:
  - For Bash code, use bash-library-template skill
  - Use relevant skills to properly use the existing libraries in new code
  - Run unit tests for modified components
  - Execute integration tests
  - Perform manual testing as needed
  - Ensure all tests pass
  - Expand the test suite to cover edge cases
- **Validation**: Test results documented and approved
- **Prohibition**: Updating the tests developed at step 4 at this stage, is prohibited

### Step 6: Documentation Updates
- **Objective**: Update all relevant documentation
- **Activities**:
  - Update code comments and docstrings
  - Modify README, API docs, Sphinx docs, AI skills or user guides
  - Document breaking changes, new features, error codes and edge-case behavior
- **Constraint**: Documentation changes must align with code changes
- **Validation**: Using sphinx-docs skill, ensure that documentation builds. 

### Step 7: Code Review Request
- **Objective**: Request peer review of changes
- **Activities**:
  - Create pull request with clear description
  - Reference the original issue
  - Assign the maintainers team as reviewers
  - Address review feedback iteratively
- **Validation**: All review comments resolved and pull request approved

### Step 8: Final Integration
- **Objective**: Merge approved changes
- **Activities**:
  - Ensure CI/CD checks pass
  - Perform final merge (squash or merge commit)
  - Close the related issue
  - Update any dependent issues
- **Validation**: Changes successfully integrated

### Step 9: Post-Implementation Validation
- **Objective**: Confirm successful deployment
- **Activities**:
  - Monitor for any issues post-merge
  - Update release notes if applicable
  - Communicate changes to stakeholders
  - Archive branch if no longer needed
- **Completion**: Issue fully resolved and validated

## Resources

This skill includes example resource directories that demonstrate how to organize different types of bundled resources:

### scripts/
Executable code (Python/Bash/etc.) that can be run directly to perform specific operations.

**Examples from other skills:**
- PDF skill: `fill_fillable_fields.py`, `extract_form_field_info.py` - utilities for PDF manipulation
- DOCX skill: `document.py`, `utilities.py` - Python modules for document processing
- Software Configuration Management: `detect_unguarded_calls.sh` - security analysis script for Bash libraries

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
