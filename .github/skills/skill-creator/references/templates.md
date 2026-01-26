# Skill Type Templates

This file contains complete templates for different types of skills.

## Minimal Skill Template

For simple, focused skills:

```markdown
---
name: simple-skill
description: Does one thing well. Triggers on "simple task".
---

# Simple Skill

## Purpose

What this skill does.

## Usage

\`\`\`bash
# How to use it
command --args
\`\`\`

## Example

\`\`\`bash
# Complete example
example_command input
\`\`\`

## Tips

- Key point 1
- Key point 2
```

## Standard Skill Template

For most skills:

```markdown
---
name: standard-skill
description: Comprehensive guidance on a topic. Triggers on "topic help".
---

# Standard Skill

## Purpose

Detailed explanation of the skill's purpose and value.

## Quick Start

\`\`\`bash
# Minimal working example
quick_example
\`\`\`

## Main Content

### Core Concept 1

Explanation with examples.

### Core Concept 2

More guidance.

## Patterns

### Pattern 1

\`\`\`bash
# Pattern example
\`\`\`

### Pattern 2

\`\`\`bash
# Another pattern
\`\`\`

## Examples

### Basic Example

\`\`\`bash
# Code
\`\`\`

### Advanced Example

\`\`\`bash
# Code
\`\`\`

## Reference

- [Template docs](references/templates.md)
- [Examples](references/examples.md)

## Tips

- Helpful tip 1
- Helpful tip 2
```

## Comprehensive Skill Template

For complex topics requiring detailed guidance:

```markdown
---
name: comprehensive-skill
description: Expert guidance on complex-topic with extensive examples and patterns. Triggers on "complex-topic help" or "work with complex-topic".
---

# Comprehensive Skill

## Purpose

Detailed purpose and scope of this skill.

## Overview

High-level introduction to the topic.

## Quick Start

### Minimal Example

\`\`\`bash
# Simplest possible example
\`\`\`

### Common Use Case

\`\`\`bash
# Most common scenario
\`\`\`

## Core Concepts

### Concept 1: [Name]

**What it is**: Definition

**Why it matters**: Explanation

**How to use it**:

\`\`\`bash
# Example
\`\`\`

### Concept 2: [Name]

Similar structure...

## Detailed Guidance

### Topic 1

In-depth explanation with multiple examples.

#### Sub-topic 1.1

Details...

#### Sub-topic 1.2

Details...

### Topic 2

More guidance...

## Common Patterns

### Pattern 1: [Name]

**When to use**: Scenario description

**Implementation**:

\`\`\`bash
# Code
\`\`\`

**Pros**:
- Advantage 1
- Advantage 2

**Cons**:
- Limitation 1

### Pattern 2: [Name]

Similar structure...

## Decision Guide

Choose the right approach:

| Scenario | Recommended Approach | Reason |
|----------|---------------------|--------|
| When X | Use pattern A | Because... |
| When Y | Use pattern B | Because... |

## Examples

### Example 1: [Basic Case]

**Scenario**: Description

**Solution**:

\`\`\`bash
# Complete code
\`\`\`

**Explanation**: Why this works

### Example 2: [Complex Case]

Similar structure...

## Best Practices

### Do's

✓ Practice 1
✓ Practice 2

### Don'ts

✗ Anti-pattern 1
✗ Anti-pattern 2

## Troubleshooting

### Problem 1

**Symptoms**: What you see

**Cause**: Why it happens

**Solution**:
\`\`\`bash
# Fix
\`\`\`

### Problem 2

Similar structure...

## Advanced Topics

### Advanced Topic 1

For power users...

### Advanced Topic 2

For specific scenarios...

## Reference Materials

- [Detailed templates](references/templates.md)
- [More examples](references/examples.md)
- [Helper scripts](references/scripts/)

## Related Skills

- **skill-1**: When to use instead
- **skill-2**: Complementary skill
- **skill-3**: Related functionality

## Checklist

When using this skill:

- [ ] Task 1
- [ ] Task 2
- [ ] Task 3

## FAQ

**Q: Common question?**

A: Answer with example if needed.

**Q: Another question?**

A: Answer...

## Additional Resources

- External link 1
- External link 2

## Tips and Tricks

1. **Pro tip 1**: Explanation
2. **Pro tip 2**: Explanation
3. **Pro tip 3**: Explanation

## Caveats and Limitations

- **Caveat 1**: What to watch out for
- **Caveat 2**: Known limitation
- **Caveat 3**: Edge case behavior

## Version History

Last updated: YYYY-MM-DD
- What changed in this version
```

## Reference File Templates

### templates.md Structure

```markdown
# [Topic] Templates

## Template 1: [Name]

\`\`\`bash
# Complete, copy-pasteable code template
\`\`\`

**Usage**:
- When to use this template
- What to customize

## Template 2: [Name]

Similar structure...
```

### examples.md Structure

```markdown
# [Topic] Examples

## Example 1: [Scenario]

### Context

What this example demonstrates.

### Problem

What challenge this solves.

### Solution

\`\`\`bash
# Complete working code
\`\`\`

### Explanation

Step-by-step breakdown of how it works.

### Variations

- Variation 1: How to adapt for X
- Variation 2: How to adapt for Y

## Example 2: [Scenario]

Similar structure...
```

## Skill Metadata

### Essential Frontmatter

```yaml
---
name: skill-name          # Required: kebab-case identifier
description: Brief desc   # Required: includes trigger phrases
---
```

### Extended Frontmatter (Optional)

```yaml
---
name: skill-name
description: Brief description with trigger phrases
version: 1.0.0           # Optional: semantic version
category: tool           # Optional: tool|template|process|security
tags:                    # Optional: searchable tags
  - bash
  - library
  - testing
author: Name             # Optional: skill author
updated: 2024-01-26      # Optional: last update date
related:                 # Optional: related skills
  - other-skill-1
  - other-skill-2
---
```

## File Organization Patterns

### Simple Skill

```
skill-name/
└── SKILL.md
```

### Standard Skill

```
skill-name/
├── SKILL.md
└── references/
    └── templates.md
```

### Complex Skill

```
skill-name/
├── SKILL.md
└── references/
    ├── templates.md
    ├── examples.md
    ├── advanced.md
    └── scripts/
        ├── helper1.sh
        └── helper2.sh
```

## Content Length Guidelines

- **Minimal skill**: 100-300 words in SKILL.md
- **Standard skill**: 300-1000 words in SKILL.md
- **Comprehensive skill**: 1000-3000 words in SKILL.md + references
- **Reference files**: No limit, but keep focused

## Writing Style Guide

### Voice and Tone

- **Active voice**: "Use this function" not "This function can be used"
- **Direct**: "Do X" not "You might want to consider doing X"
- **Confident**: "This solves Y" not "This might help with Y"
- **Concise**: Remove unnecessary words

### Code Examples

- **Complete**: Can be copied and run
- **Commented**: Explain non-obvious parts
- **Realistic**: Based on real use cases
- **Tested**: Verify examples work

### Formatting

- **Headings**: Use clear, descriptive headings
- **Lists**: Break up text with bullet points
- **Code blocks**: Always specify language
- **Tables**: Use for comparisons and reference data
- **Emphasis**: Use bold for important terms, italic for emphasis

## Skill Naming Patterns

- **Tool skills**: `tool-name` (e.g., `handle-state`)
- **Template skills**: `component-template` (e.g., `bash-library-template`)
- **Process skills**: `action-workflow` (e.g., `github-issues`)
- **Security skills**: `security-checker` (e.g., `bash-path-prefix-scan`)
- **Meta skills**: `meta-skill` (e.g., `skill-creator`)
