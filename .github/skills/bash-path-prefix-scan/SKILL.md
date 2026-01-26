---
name: bash-path-prefix-scan
description: Scan Bash scripts for PATH prefix vulnerabilities by identifying external commands not shadowed by Bash functions; report findings and file GitHub minor issues for each uncovered command.
---

# Bash PATH Prefix Scan

Use this skill when the user asks to scan Bash scripts for PATH prefix vulnerabilities or to audit external command usage.

## Workflow

1. **Confirm scope**
   - Use files the user names, or list Bash files with `rg --files -g '*.sh'`.
   - Include scripts without `.sh` if they have a Bash shebang.

2. **Collect function overrides**
   - Parse each file for function definitions: `name()` and `function name`.
   - Track function names per file and from sourced files (`source` or `.`) when provided.

3. **Identify command invocations**
   - For each command word, ignore Bash keywords and builtins.
   - Treat the remaining command words as external commands.
   - If an external command name matches a function name in scope, it is shadowed; otherwise it is vulnerable.

4. **Report findings**
   - List each vulnerable command with `path:line` and the command name.
   - Note when a call site is ambiguous (dynamic invocation, eval, or variable indirection).

5. **Create GitHub minor issues**
   - For every external command that is not shadowed by a function, file a minor issue.
   - Use the `github-issues` skill and its Task template.

## Classification Rules

- **Bash keywords**: `if`, `then`, `else`, `elif`, `fi`, `for`, `while`, `until`, `case`, `esac`, `select`, `in`, `do`, `done`, `function`, `time`, `coproc`.
- **Bash builtins**: use `compgen -b` or `help` when available; otherwise treat the common builtins as safe.
- **External commands**: any command word that is neither a keyword, builtin, nor function.

## Issue Format (minor)

- **Title**: `[Security][Minor] Add function override for <command> in <file>`
- **Body** (Task template): include summary, file path, line(s), and recommended function wrapper name.
- **Labels**: `bug` and `security` if available; otherwise omit labels.

## Notes

- Function overrides must be defined before use or sourced from known files.
- If scope is unclear or external tooling is required, ask a brief clarifying question.
