#!/usr/bin/env bats

# Bats tests for LIB_NAME
# Run with: bats test/test-LIB_NAME.bats

setup_file() {
  bats_require_minimum_version 1.5.0
  export LIB="$BATS_TEST_DIRNAME/../LIB_FILE"
  if [ ! -f "$LIB" ]; then
    echo "Missing library $LIB" >&2
    return 1
  fi
  # shellcheck source=../LIB_FILE
  source "$LIB"
}

# This test is intentionally skipped by default to avoid breaking the suite.
# Set LIB_TEMPLATE_RUN_FAILING_TESTS=1 to enable and confirm failure until implemented.
@test "LIB_PREFIX_example placeholder fails until implemented" {
  if [ -z "${LIB_TEMPLATE_RUN_FAILING_TESTS:-}" ]; then
    skip "Template placeholder test disabled by default"
  fi
  LIB_PREFIX_example "arg1" "arg2"
  # Fails by default so the new library gets real tests.
  false
}
