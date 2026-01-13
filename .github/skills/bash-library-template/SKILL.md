---
name: bash-library-template
description: Create new Bash shell libraries using a standardized template based on config/handle_state.sh, and initialize matching documentation in docs/libraries.
---

# Bash Library Template

Use this skill when the user asks to create a new Bash library, scaffold a Bash library file, or add library documentation.

## Assets

- `assets/bash_library_template.sh`: base library template modeled after `config/handle_state.sh`.
- `assets/bash_library_test_template.bats`: unit test template for the library.

## Workflow

1. **Pick names**
   - Library file path (e.g., `config/<library>.sh`).
   - Function prefix (e.g., `hs_`), and include guard name (e.g., `__LIB_<NAME>_INCLUDED`).

2. **Create the library file**
   - Copy the template from `assets/bash_library_template.sh`.
   - Replace placeholders: `LIB_NAME`, `LIB_FILE`, `LIB_PREFIX`, `INCLUDE_GUARD`.
   - Keep sections and comment layout consistent with `config/handle_state.sh`.

3. **Initialize documentation**
   - Create `docs/libraries/<library>.rst` with the section headings and boilerplate from the template.
   - Add the new doc file to `docs/libraries/index.rst` under the toctree.

4. **Initialize unit tests**
   - Create `test/test-<library>.bats` from `assets/bash_library_test_template.bats`.
   - Replace placeholders: `LIB_NAME`, `LIB_FILE`, `LIB_PREFIX`.
   - Keep the default test skipped unless an env flag is set, so the suite passes by default.

5. **Verify**
   - Ensure the include guard prevents double-sourcing.
   - Ensure public API functions use the `LIB_PREFIX`.

## Notes

- Prefer plain Bash constructs; avoid external dependencies.
- Keep the template ASCII-only.
