---
name: bash-library-template
description: Expert guidance for creating new Bash libraries following established patterns in this repository. Provides templates, structure guidelines, and best practices for library development. Triggers on requests like "create a new library", "new bash module", or "library template".
---

# Bash Library Template Skill

## Purpose

This skill provides templates and guidance for creating new Bash libraries that follow the established patterns in this repository. Use it when creating new reusable Bash modules or libraries.

## Library Structure

A well-structured Bash library should include:

1. **Source File** (`config/<library-name>.sh`)
   - Contains the library implementation
   - Should be sourceable (not executable)
   - Uses functions with a consistent prefix

2. **Documentation** (`docs/libraries/<library-name>.rst`)
   - Sphinx-compatible RST format
   - Includes API reference, examples, and caveats

3. **Tests** (`test/<library-name>_test.sh`)
   - Unit tests using appropriate testing framework
   - Covers main use cases and edge cases

## Quick Start

### Creating a New Library

1. **Create the library file**:
   ```bash
   touch config/my_library.sh
   chmod 644 config/my_library.sh
   ```

2. **Use the template from** [references/templates.md](references/templates.md)

3. **Create documentation**:
   ```bash
   touch docs/libraries/my_library.rst
   ```

4. **Add to documentation index**:
   Edit `docs/libraries/index.rst` to include your new library

5. **Create tests**:
   ```bash
   touch test/my_library_test.sh
   chmod 755 test/my_library_test.sh
   ```

## Best Practices

### Naming Conventions

- **Function names**: Use a consistent prefix (e.g., `ml_` for "my_library")
- **Variable names**: Use descriptive names, avoid generic names like `tmp`
- **Constants**: Use UPPERCASE for library constants (e.g., `ML_ERROR_CODE=1`)

### Error Handling

- Return explicit error codes (don't rely on `set -e`)
- Use distinct error codes for different failure modes
- Print clear error messages to stderr
- Document error codes in the library documentation

### State Management

- Use `handle_state.sh` for passing state between functions
- Keep state minimal - only persist what's necessary
- Document what state is persisted and how to consume it

### Output Handling

- Use `hs_echo` for messages from init functions (when stdout captures state)
- Direct normal output to stdout
- Send errors and warnings to stderr
- Consider providing both verbose and quiet modes

### Documentation

- Follow RST format for consistency
- Include:
  - Purpose section
  - Quick Start with minimal example
  - Public API documentation
  - Error codes table
  - Examples section
  - Caveats/warnings

## Integration with handle_state.sh

If your library needs to pass state from initialization to cleanup:

```bash
source "$(dirname "$0")/config/handle_state.sh"

ml_init() {
    hs_echo "Initializing my library..."
    local resource_id="res_123"
    local temp_file="/tmp/mylib_temp"
    ml_persist_state resource_id temp_file
}

ml_persist_state() {
    hs_persist_state "$@"
}

ml_cleanup() {
    local resource_id temp_file
    eval "$1"
    rm -f "$temp_file"
    hs_echo "Cleaned up resource: $resource_id"
}
```

## Testing Guidelines

- Test both success and failure paths
- Test with valid and invalid inputs
- Test state persistence if applicable
- Consider testing with different Bash versions if compatibility matters
- Use descriptive test names

## Common Patterns

### Option Parsing

```bash
ml_function() {
    local verbose=false
    local input=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            -i|--input)
                input="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    
    # Function logic here
}
```

### Validation

```bash
ml_validate_input() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        echo "Error: input cannot be empty" >&2
        return 1
    fi
    
    if [[ ! -f "$input" ]]; then
        echo "Error: file not found: $input" >&2
        return 2
    fi
    
    return 0
}
```

## Examples

See [references/templates.md](references/templates.md) for complete templates including:
- Basic library template
- Library with state management
- Library with option parsing
- Test template

## Related Skills

- **handle-state**: For state persistence patterns
- **sphinx-docs**: For documentation guidelines

## Tips

- Start simple - add complexity only as needed
- Keep functions focused on single responsibilities
- Make libraries composable - avoid tight coupling
- Consider backwards compatibility when updating
- Version your libraries if they're used externally
