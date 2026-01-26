---
name: skill-creator
description: Comprehensive guide for creating GitHub Copilot skills. Provides structure, templates, best practices, and scripts for building effective custom skills. Triggers on requests like "create a skill", "new skill", "skill template", or "skill development guide".
---

# Skill Creator Skill

## Purpose

This skill provides comprehensive guidance for creating effective GitHub Copilot skills. It covers skill structure, content guidelines, trigger patterns, and best practices for building specialized skills that enhance the development workflow.

## What is a Skill?

A skill is a specialized knowledge module that provides expert guidance to GitHub Copilot on a specific topic or task. Skills help Copilot:
- Provide domain-specific expertise
- Follow project-specific patterns
- Apply best practices consistently
- Automate common workflows

## Skill Structure

Each skill consists of:

```
.github/skills/<skill-name>/
├── SKILL.md              # Main skill file with frontmatter and content
└── references/           # Supporting materials (optional)
    ├── templates.md      # Code templates
    ├── examples.md       # Examples and use cases
    └── scripts/          # Helper scripts (optional)
```

## SKILL.md Format

### Frontmatter

Every SKILL.md starts with YAML frontmatter:

```yaml
---
name: skill-name
description: Brief description of when to use this skill. Include trigger patterns like "when X" or "requests like 'Y'".
---
```

**Requirements**:
- `name`: Kebab-case identifier (e.g., `bash-library-template`)
- `description`: 1-3 sentences including:
  - What the skill provides
  - When it should be used
  - Example trigger phrases (e.g., "Triggers on requests like 'create a library'")

### Content Sections

A well-structured skill includes:

1. **Purpose** (required)
   - Clear explanation of what the skill does
   - Why it exists

2. **Overview/Quick Start** (recommended)
   - Quick example showing the skill in action
   - Minimal steps to get started

3. **Main Content** (required)
   - Detailed guidance
   - Patterns and best practices
   - API reference (if applicable)

4. **Examples** (highly recommended)
   - Real-world use cases
   - Before/after comparisons
   - Common scenarios

5. **Reference Links** (if applicable)
   - Links to [references/](references/) files
   - External documentation
   - Related skills

6. **Tips/Caveats** (recommended)
   - Common pitfalls
   - Important warnings
   - Pro tips

## Writing Effective Skills

### Do's

✓ **Be specific and actionable**
- Provide concrete examples
- Include code snippets
- Show complete workflows

✓ **Use clear structure**
- Use headings consistently
- Break content into digestible sections
- Use lists and tables for clarity

✓ **Include trigger patterns**
- Define clear scenarios when the skill applies
- Use phrases users might say
- Document in description field

✓ **Link to references**
- Keep SKILL.md focused
- Move detailed templates to references/
- Provide quick access to examples

✓ **Follow established patterns**
- Look at existing skills for inspiration
- Match the tone and style of the project
- Use consistent formatting

### Don'ts

✗ **Don't be vague**
- Avoid generic advice without examples
- Don't assume knowledge not in the skill
- Don't use undefined terms without explanation

✗ **Don't duplicate content**
- Use references/ for detailed content
- Link rather than repeat
- Keep SKILL.md as overview

✗ **Don't ignore context**
- Consider the project structure
- Reference actual files in the project
- Align with project conventions

## Skill Categories

### Tool/Library Skills
Guide usage of specific tools or libraries in the project.

**Example**: `handle-state` skill for state management library

**Key sections**:
- API reference
- Usage patterns
- Error codes
- Integration examples

### Template Skills
Provide scaffolding for creating new components.

**Example**: `bash-library-template` skill for creating new libraries

**Key sections**:
- Structure guidelines
- Code templates
- Best practices
- Testing approach

### Process Skills
Guide specific workflows or procedures.

**Example**: `github-issues` skill for creating issues

**Key sections**:
- Workflow steps
- Templates
- Decision trees
- Common scenarios

### Security Skills
Help identify and fix security issues.

**Example**: `bash-path-prefix-scan` skill for PATH vulnerabilities

**Key sections**:
- Vulnerability patterns
- Detection methods
- Remediation steps
- Secure alternatives

## Creating a New Skill

### Step 1: Plan the Skill

Answer these questions:
- What specific problem does this skill solve?
- When should Copilot use this skill?
- What knowledge does it provide?
- What are common trigger phrases?

### Step 2: Create the Structure

```bash
# Create skill directory
mkdir -p .github/skills/<skill-name>/references

# Create main skill file
touch .github/skills/<skill-name>/SKILL.md
```

### Step 3: Write the Frontmatter

```yaml
---
name: skill-name
description: What it does and when to use it. Triggers on "example phrase".
---
```

### Step 4: Write Core Content

Follow the template in [references/skill-template.md](references/skill-template.md)

Key sections:
- Purpose
- Quick Start
- Main guidance
- Examples
- Tips

### Step 5: Add References (Optional)

Create supporting files:
- `references/templates.md` - Code templates
- `references/examples.md` - Detailed examples
- `references/scripts/` - Helper scripts

### Step 6: Test the Skill

- Verify frontmatter YAML is valid
- Check all links work
- Ensure code examples are correct
- Test with actual use cases

### Step 7: Document Integration

Update project documentation:
- List the new skill
- Explain when to use it
- Link to the skill

## Skill Templates

See [references/skill-template.md](references/skill-template.md) for a complete skill template.

See [references/templates.md](references/templates.md) for templates for different skill types:
- Tool/Library skill template
- Template/Generator skill template
- Process/Workflow skill template
- Security/Checker skill template

## Best Practices

### Content Quality

1. **Be comprehensive but focused**
   - Cover the topic thoroughly
   - Stay on topic
   - Link to external resources for deep dives

2. **Use examples liberally**
   - Show, don't just tell
   - Include both good and bad examples
   - Provide context for each example

3. **Keep it up-to-date**
   - Review skills regularly
   - Update when APIs change
   - Archive obsolete skills

### Naming

1. **Use kebab-case** for skill names
2. **Be descriptive**: `bash-library-template` not `template`
3. **Avoid acronyms** unless widely known

### Organization

1. **One skill per topic**: Don't combine unrelated topics
2. **Cross-reference related skills**: Link to complementary skills
3. **Keep files manageable**: Use references/ for long content

### Trigger Patterns

1. **Be explicit**: Include trigger phrases in description
2. **Think like a user**: What would they ask?
3. **Cover variations**: "create issue", "file bug", "open issue"

## Helper Scripts

The [references/scripts/](references/scripts/) directory contains:
- `create-skill.sh` - Interactive skill creator
- `validate-skill.sh` - Validate skill format
- `list-skills.sh` - List all skills with metadata

## Examples of Great Skills

### Example 1: Tool Skill (handle-state)

**Strengths**:
- Clear API reference
- Complete working examples
- Links to comprehensive documentation
- Covers limitations and workarounds

**Structure**:
```
- Purpose
- Quick Workflow
- Standard Pattern
- Logging Guidance
- Supported Variables
- Limitations
- Workarounds
- Safety Notes
```

### Example 2: Process Skill (github-issues)

**Strengths**:
- Clear workflow steps
- Multiple templates
- Decision guidance
- Real examples with JSON

**Structure**:
```
- Overview
- Available Tools
- Workflow
- Creating Issues (with guidelines)
- Templates
- Examples
- Tips
```

### Example 3: Template Skill (bash-library-template)

**Strengths**:
- Complete structure guidelines
- Multiple code templates
- Best practices
- Testing guidance

**Structure**:
```
- Purpose
- Structure
- Quick Start
- Best Practices
- Common Patterns
- Examples (in references/)
- Related Skills
```

## Skill Discovery

Skills are discovered by Copilot based on:
1. **Description triggers**: Phrases in the description
2. **Content relevance**: Keywords in the skill content
3. **User queries**: Matching user's request to skill topics

Make your skill discoverable:
- Use clear, specific language in description
- Include common terminology
- Add trigger phrases explicitly

## Validation

Before publishing a skill:

- [ ] YAML frontmatter is valid
- [ ] Name is kebab-case and descriptive
- [ ] Description includes trigger patterns
- [ ] All sections have content
- [ ] Code examples are tested
- [ ] Links are valid
- [ ] References exist if mentioned
- [ ] Formatting is consistent
- [ ] No typos or grammar issues

## Continuous Improvement

Improve skills over time:
1. **Monitor usage**: Which skills are used most?
2. **Gather feedback**: What's missing or unclear?
3. **Update regularly**: Keep content current
4. **Refactor when needed**: Split large skills, merge small ones
5. **Archive deprecated skills**: Remove outdated content

## Related Skills

- **bash-library-template**: Example of template skill
- **github-issues**: Example of process skill
- **handle-state**: Example of tool skill
- **bash-path-prefix-scan**: Example of security skill

## Additional Resources

- [references/skill-template.md](references/skill-template.md) - Blank skill template
- [references/templates.md](references/templates.md) - Type-specific templates
- [references/scripts/create-skill.sh](references/scripts/create-skill.sh) - Skill creation wizard

## Tips for Success

1. **Start simple**: Create a basic skill, refine iteratively
2. **Use existing skills as reference**: Learn from what works
3. **Test with real scenarios**: Verify the skill helps actual tasks
4. **Get feedback**: Have others review and use your skill
5. **Keep it focused**: One skill, one topic
6. **Document assumptions**: Make prerequisites clear
7. **Version your skills**: Note when content was last updated
8. **Be practical**: Focus on real-world usage over theory
