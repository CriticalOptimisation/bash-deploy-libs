# Bash Library Templates

## Basic Library Template

```bash
#!/usr/bin/env bash
# Library: my_library.sh
# Purpose: Brief description of what this library does
# Usage: source this file, then call ml_* functions

# Error codes
readonly ML_ERR_INVALID_INPUT=1
readonly ML_ERR_FILE_NOT_FOUND=2
readonly ML_ERR_OPERATION_FAILED=3

# Main library function
ml_do_something() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        echo "Error: input parameter is required" >&2
        return "$ML_ERR_INVALID_INPUT"
    fi
    
    # Function implementation here
    echo "Processing: $input"
    
    return 0
}

# Validation helper
ml_validate_input() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        echo "Error: input cannot be empty" >&2
        return "$ML_ERR_INVALID_INPUT"
    fi
    
    return 0
}
```

## Library with State Management

```bash
#!/usr/bin/env bash
# Library: stateful_library.sh
# Purpose: Library that persists state from initialization to cleanup

# Source handle_state library
source "$(dirname "${BASH_SOURCE[0]}")/handle_state.sh"

# Error codes
readonly SL_ERR_INIT_FAILED=1
readonly SL_ERR_CLEANUP_FAILED=2

# Initialize library resources
sl_init() {
    local config_file="${1:-/etc/default/config}"
    
    hs_echo "Initializing stateful library..."
    
    # Create temporary resources
    local temp_dir
    temp_dir=$(mktemp -d)
    if [[ ! -d "$temp_dir" ]]; then
        echo "Error: failed to create temp directory" >&2
        return "$SL_ERR_INIT_FAILED"
    fi
    
    local session_id="session_$$_$(date +%s)"
    
    hs_echo "Created temp dir: $temp_dir"
    hs_echo "Session ID: $session_id"
    
    # Persist state for cleanup
    sl_persist_state temp_dir session_id config_file
}

# Wrapper for handle_state persistence
sl_persist_state() {
    hs_persist_state "$@"
}

# Cleanup library resources
sl_cleanup() {
    local state="$1"
    local temp_dir session_id config_file
    
    # Restore state
    eval "$state"
    
    hs_echo "Cleaning up session: $session_id"
    
    # Clean up resources
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        hs_echo "Removed temp dir: $temp_dir"
    fi
    
    return 0
}

# Main library operation
sl_process() {
    local state="$1"
    local input="$2"
    local temp_dir session_id config_file
    
    # Restore state
    eval "$state"
    
    # Use the state to perform operations
    echo "Processing $input in session $session_id"
    echo "Using temp dir: $temp_dir"
    echo "Config: $config_file"
    
    return 0
}
```

## Library with Option Parsing

```bash
#!/usr/bin/env bash
# Library: option_library.sh
# Purpose: Library with comprehensive option parsing

# Error codes
readonly OL_ERR_INVALID_OPTION=1
readonly OL_ERR_MISSING_VALUE=2

# Main function with options
ol_process() {
    local verbose=false
    local output_file=""
    local input_file=""
    local force=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --output requires a value" >&2
                    return "$OL_ERR_MISSING_VALUE"
                fi
                output_file="$2"
                shift 2
                ;;
            -i|--input)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --input requires a value" >&2
                    return "$OL_ERR_MISSING_VALUE"
                fi
                input_file="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                ol_show_help
                return 0
                ;;
            -*)
                echo "Error: unknown option: $1" >&2
                ol_show_help
                return "$OL_ERR_INVALID_OPTION"
                ;;
            *)
                echo "Error: unexpected argument: $1" >&2
                return "$OL_ERR_INVALID_OPTION"
                ;;
        esac
    done
    
    # Validate required options
    if [[ -z "$input_file" ]]; then
        echo "Error: --input is required" >&2
        return "$OL_ERR_MISSING_VALUE"
    fi
    
    # Function logic
    if $verbose; then
        echo "Processing $input_file..."
    fi
    
    # Implementation here
    
    return 0
}

# Show help message
ol_show_help() {
    cat <<EOF
Usage: ol_process [OPTIONS]

Options:
  -i, --input FILE     Input file (required)
  -o, --output FILE    Output file (optional)
  -v, --verbose        Enable verbose output
  -f, --force          Force operation
  -h, --help           Show this help message

Example:
  ol_process --input data.txt --output result.txt --verbose
EOF
}
```

## Test Template

```bash
#!/usr/bin/env bash
# Tests for my_library.sh

# Source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/my_library.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test helper functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ PASS: $message"
        return 0
    else
        echo "✗ FAIL: $message"
        echo "  Expected: $expected"
        echo "  Got: $actual"
        return 1
    fi
}

assert_success() {
    local command="$1"
    local message="${2:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$command" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ PASS: $message"
        return 0
    else
        echo "✗ FAIL: $message"
        echo "  Command failed: $command"
        return 1
    fi
}

assert_failure() {
    local command="$1"
    local message="${2:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! eval "$command" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ PASS: $message"
        return 0
    else
        echo "✗ FAIL: $message"
        echo "  Command should have failed: $command"
        return 1
    fi
}

# Test cases
test_basic_functionality() {
    echo "=== Test: Basic Functionality ==="
    
    local result
    result=$(ml_do_something "test_input")
    assert_equals "Processing: test_input" "$result" "Basic processing works"
}

test_error_handling() {
    echo "=== Test: Error Handling ==="
    
    assert_failure 'ml_do_something ""' "Empty input should fail"
    assert_failure 'ml_do_something' "Missing input should fail"
}

test_validation() {
    echo "=== Test: Input Validation ==="
    
    assert_success 'ml_validate_input "valid"' "Valid input accepted"
    assert_failure 'ml_validate_input ""' "Empty input rejected"
}

# Run all tests
main() {
    echo "Running tests for my_library.sh..."
    echo ""
    
    test_basic_functionality
    echo ""
    
    test_error_handling
    echo ""
    
    test_validation
    echo ""
    
    # Summary
    echo "================================"
    echo "Tests run: $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $((TESTS_RUN - TESTS_PASSED))"
    
    if [[ $TESTS_RUN -eq $TESTS_PASSED ]]; then
        echo "All tests passed! ✓"
        exit 0
    else
        echo "Some tests failed! ✗"
        exit 1
    fi
}

main "$@"
```

## Documentation Template (RST)

```rst
My Library
==========

Location
--------

- `config/my_library.sh`

Purpose
-------

Brief description of what the library does and why it exists.

Quick Start
-----------

Minimal example showing how to use the library:

.. code-block:: bash

   # Source the library
   source "path/to/config/my_library.sh"
   
   # Use the main function
   ml_do_something "input"

Public API
----------

ml_do_something
~~~~~~~~~~~~~~~

Brief description of what this function does.

- Parameters:
  - `$1`: Description of first parameter
  - `$2`: Description of second parameter (optional)
- Output: What the function outputs to stdout
- Returns: Exit code (0 for success, non-zero for errors)
- Errors:
  - `ML_ERR_INVALID_INPUT` (1): Input validation failed
  - `ML_ERR_OPERATION_FAILED` (3): Operation failed

Usage:

.. code-block:: bash

   ml_do_something "my_input"

ml_validate_input
~~~~~~~~~~~~~~~~~

Validates input before processing.

- Parameters:
  - `$1`: Input to validate
- Returns: 0 if valid, 1 if invalid

Error Codes
-----------

- `ML_ERR_INVALID_INPUT=1`: Input validation failed
- `ML_ERR_FILE_NOT_FOUND=2`: Required file not found
- `ML_ERR_OPERATION_FAILED=3`: Operation failed

Examples
--------

Example 1: Basic Usage
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   source "config/my_library.sh"
   ml_do_something "test"

Example 2: With Error Handling
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   source "config/my_library.sh"
   
   if ml_do_something "test"; then
       echo "Success"
   else
       echo "Failed with code: $?"
   fi

Caveats
-------

- List any known limitations
- Describe edge cases or special considerations
- Note any dependencies on other libraries or tools

Source Listing
--------------

.. literalinclude:: ../../config/my_library.sh
   :language: bash
   :linenos:
```
