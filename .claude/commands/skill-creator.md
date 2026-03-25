---
description: Guide for creating effective Claude Code skills (slash commands). Use this skill when users want to create a new skill or update an existing skill that extends Claude's capabilities with specialized knowledge, workflows, or tool integrations.
---

# Skill Creator

This skill provides guidance for creating effective Claude Code slash commands (skills).

## About Skills

Skills are `.md` files in `.claude/commands/`. Each file becomes a `/command-name` slash command. The file content is injected as context when the command is invoked.

### What Skills Provide

1. Specialized workflows — multi-step procedures for specific domains
2. Tool integrations — instructions for working with specific file formats or APIs
3. Domain expertise — project-specific knowledge, schemas, business logic
4. Pointers to bundled resources — scripts, references, and assets in `.github/skills/`

## Core Principles

### Be Concise

The context window is a shared resource. Only add context Claude doesn't already have. Challenge each piece of information: "Does Claude really need this?" Prefer short examples over verbose explanations.

### Set Appropriate Degrees of Freedom

- **High freedom** (text instructions): multiple approaches are valid
- **Medium freedom** (pseudocode/scripts with parameters): a preferred pattern exists
- **Low freedom** (specific scripts, few parameters): operations are fragile or must be consistent

### Anatomy of a Claude Code Skill

```
.claude/commands/
└── skill-name.md          ← slash command file (required)

.github/skills/skill-name/ ← companion resources (optional, referenced by path)
    ├── scripts/           ← executable scripts
    ├── references/        ← documentation loaded on demand
    └── assets/            ← templates and output files
```

#### Frontmatter (required)

```yaml
---
description: What the skill does AND when to use it. This is shown in /help and
             used by the Skill tool to match user requests. Be specific.
---
```

#### Body (markdown instructions)

- Instructions for executing the skill
- Paths to companion resources in `.github/skills/<name>/` when they exist
- Keep under ~300 lines; move detail to reference files

## Skill Creation Workflow

1. **Understand the skill** — clarify use cases and triggers with the user
2. **Plan resources** — identify scripts, references, or assets needed
3. **Create the command file** — write `.claude/commands/<name>.md`
4. **Add companion resources** — place in `.github/skills/<name>/` if needed; reference by path from the command file
5. **Iterate** — refine based on actual usage

## Writing the Description

The `description` field is the primary trigger. Include:
- What the skill does
- Specific situations when it should be used
- Key trigger phrases

Example:
```yaml
description: Create and manage Sphinx RST documentation. Use when asked to write
             docs, update toctrees, add API references, or integrate docs into CI.
```

## Reference Files

For skills with substantial reference material, store it in `.github/skills/<name>/references/` and link to it from the command file with the project-root-relative path. Claude reads these files on demand using the Read tool.

See `.github/skills/skill-creator/references/` for additional guidance on workflows and output patterns.
