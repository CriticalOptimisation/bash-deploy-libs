# Skill Template

Use this template as a starting point for creating new skills.

## Basic Skill Template

```markdown
---
name: my-skill-name
description: Brief description of what this skill does. Triggers on requests like "example trigger phrase" or "another trigger".
---

# My Skill Name

## Purpose

Clear, concise explanation of what this skill provides and why it exists.

## Quick Start

Minimal example showing the most common use case:

\`\`\`bash
# Example command or code
do_something --with-args
\`\`\`

## Main Content

### Section 1: Core Concepts

Explain the main concepts or patterns this skill addresses.

### Section 2: Usage

Detailed guidance on how to use the skill knowledge.

\`\`\`bash
# More detailed example
function example() {
    # Implementation
}
\`\`\`

### Section 3: Common Patterns

List common patterns or scenarios:

1. **Pattern 1**: Description
2. **Pattern 2**: Description
3. **Pattern 3**: Description

## Examples

### Example 1: Basic Usage

\`\`\`bash
# Show a complete, working example
example_command input output
\`\`\`

### Example 2: Advanced Usage

\`\`\`bash
# Show a more complex example
advanced_example --option value
\`\`\`

## Reference Materials

- [templates.md](references/templates.md) - Code templates
- [examples.md](references/examples.md) - Additional examples

## Related Skills

- **related-skill-1**: Brief description
- **related-skill-2**: Brief description

## Tips

- Tip 1
- Tip 2
- Tip 3

## Caveats

- Important limitation or warning
- Another caveat to be aware of
```

## Tool/Library Skill Template

For skills documenting a specific tool or library:

```markdown
---
name: tool-name
description: Expert guidance for using the tool-name library/tool. Triggers on "use tool-name" or "tool-name help".
---

# Tool Name Skill

## Purpose

What this tool does and why you'd use it.

## Quick Start

\`\`\`bash
# Source or import
source path/to/tool.sh

# Basic usage
tool_function arg1 arg2
\`\`\`

## API Reference

### function_name

Description of what this function does.

- **Parameters**:
  - `$1`: Description of first parameter
  - `$2`: Description of second parameter
- **Returns**: What the function returns
- **Errors**: Error codes and meanings

\`\`\`bash
# Usage example
function_name "value1" "value2"
\`\`\`

### another_function

Similar documentation...

## Common Patterns

### Pattern 1: Initialization

\`\`\`bash
tool_init
# Use tool
tool_cleanup
\`\`\`

### Pattern 2: With Options

\`\`\`bash
tool_function --verbose --output file.txt
\`\`\`

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | ERR_INVALID | Invalid input |
| 2 | ERR_NOT_FOUND | Resource not found |

## Examples

See [references/examples.md](references/examples.md) for complete examples.

## Tips

- Best practice 1
- Best practice 2

## Caveats

- Known limitation 1
- Known limitation 2
```

## Template/Generator Skill Template

For skills that help create new components:

```markdown
---
name: component-template
description: Template and guidance for creating new components. Triggers on "create component" or "new component".
---

# Component Template Skill

## Purpose

Provides templates and guidelines for creating new components following project conventions.

## Component Structure

A component should include:

1. **Main file** (`path/to/component.ext`)
2. **Tests** (`test/component_test.ext`)
3. **Documentation** (`docs/component.rst`)

## Quick Start

\`\`\`bash
# Create component
mkdir -p path/to/component
touch path/to/component/main.ext
\`\`\`

## Templates

See [references/templates.md](references/templates.md) for:
- Basic component template
- Component with options
- Test template
- Documentation template

## Best Practices

### Naming

- Use descriptive names
- Follow project conventions
- Avoid abbreviations

### Structure

- Keep functions focused
- Add error handling
- Document thoroughly

### Testing

- Test success paths
- Test failure paths
- Test edge cases

## Checklist

When creating a new component:

- [ ] Create main file
- [ ] Add documentation
- [ ] Write tests
- [ ] Update index/registry
- [ ] Test integration

## Examples

### Example 1: Basic Component

\`\`\`bash
# Complete example of creating a basic component
\`\`\`

## Related Skills

- **testing**: For testing guidance
- **documentation**: For docs standards

## Tips

- Start simple
- Follow existing patterns
- Get feedback early
```

## Process/Workflow Skill Template

For skills documenting a process or workflow:

```markdown
---
name: workflow-name
description: Guide for the workflow-name process. Triggers on "workflow-name" or "how to workflow".
---

# Workflow Name Skill

## Purpose

Explains how to perform [workflow] correctly and efficiently.

## Overview

Brief description of the workflow and when to use it.

## Prerequisites

- Requirement 1
- Requirement 2
- Requirement 3

## Workflow Steps

### Step 1: Preparation

What to do first.

\`\`\`bash
# Commands for step 1
prepare_command
\`\`\`

### Step 2: Main Action

What to do next.

\`\`\`bash
# Commands for step 2
main_command --args
\`\`\`

### Step 3: Verification

How to verify it worked.

\`\`\`bash
# Commands for verification
verify_command
\`\`\`

### Step 4: Cleanup (if needed)

What to clean up.

\`\`\`bash
# Cleanup commands
cleanup_command
\`\`\`

## Decision Tree

When to use which approach:

- **If X**: Do approach A
- **If Y**: Do approach B
- **Otherwise**: Do approach C

## Common Scenarios

### Scenario 1: [Common Case]

How to handle this scenario.

### Scenario 2: [Edge Case]

How to handle this scenario.

## Troubleshooting

### Problem: X doesn't work

**Solution**: Do Y

### Problem: Error Z occurs

**Solution**: Check A, then B

## Templates

See [references/templates.md](references/templates.md) for:
- Template 1
- Template 2

## Examples

Complete examples for common cases.

## Tips

- Pro tip 1
- Pro tip 2

## Common Mistakes

- Mistake 1: What not to do
- Mistake 2: What not to do
```

## Security/Checker Skill Template

For skills focused on finding and fixing issues:

```markdown
---
name: security-checker
description: Identifies and fixes security-issue. Triggers on "check for security-issue" or "scan security".
---

# Security Checker Skill

## Purpose

Helps identify and remediate [security issue] vulnerabilities.

## Overview

What the security issue is and why it matters.

## Vulnerability Patterns

### Pattern 1: [Dangerous Pattern]

\`\`\`bash
# VULNERABLE code
dangerous_pattern
\`\`\`

**Why dangerous**: Explanation

### Pattern 2: [Another Pattern]

Similar structure...

## Detection

### Manual Inspection

How to manually look for the issue:

\`\`\`bash
grep -n "pattern" file.sh
\`\`\`

### Automated Scanning

See [references/scan-script.sh](references/scan-script.sh) for automated detection.

## Remediation

### Fix 1: [Best Approach]

\`\`\`bash
# SECURE code
safe_pattern
\`\`\`

### Fix 2: [Alternative]

\`\`\`bash
# Another secure approach
alternative_pattern
\`\`\`

## Remediation Checklist

- [ ] Identify all instances
- [ ] Assess severity
- [ ] Apply fixes
- [ ] Test functionality
- [ ] Verify fix

## Examples

### Vulnerable Code

\`\`\`bash
# Show real vulnerable code
\`\`\`

### Fixed Code

\`\`\`bash
# Show the secure version
\`\`\`

## Best Practices

1. Practice 1
2. Practice 2
3. Practice 3

## References

- CWE-XXX: Vulnerability name
- Related security standards

## Tips

- Security tip 1
- Security tip 2
```
