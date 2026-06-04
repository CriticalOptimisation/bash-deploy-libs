#!/usr/bin/env bats

# Preliminary tests for config/ensure_docker.sh  (Stage 1)
# Run with: bats test/test-ensure_docker.bats
#
# Unit tests mock the docker and apt-cache binaries via a PATH-prefixed temp
# directory.  Mock behaviour is controlled by MOCK_DOCKER_* environment
# variables set per test.
#
# Integration tests require a privileged Docker-in-Docker environment and are
# skipped automatically when Docker is unavailable.
# shellcheck disable=SC2329

# ---------------------------------------------------------------------------
# Mock docker binary — behaviour controlled by environment variables
# ---------------------------------------------------------------------------
# MOCK_DOCKER_ABSENT=1   — docker binary exits 1 (simulates not found in PATH)
# MOCK_DOCKER_VERSION    — engine semver string (default: 24.0.7)
# MOCK_DOCKER_COMMIT     — git commit hash (default: abc1234)
# MOCK_COMPOSE_ABSENT=1  — docker compose subcommand exits 1
# MOCK_COMPOSE_VERSION   — compose semver (default: 2.20.0)

readonly ED_TEST_SOURCE_FAILED=2
# ED_TEST_DOCKER_NET_FAILED, ED_TEST_CONTAINER_START_FAILED, ED_TEST_CONTAINER_NOT_READY
# will be added in Stage 1 implementation when the DinD fixture is wired up.

setup_file() {
    bats_require_minimum_version 1.5.0
    export BATS_TEST_TIMEOUT=30

    export LIB="$BATS_TEST_DIRNAME/../config/ensure_docker.sh"
    if [[ ! -f "$LIB" ]]; then
        export ED_TESTS_SKIP="ensure_docker.sh not yet implemented"
        return 0
    fi

    # Create shared mock binary directory
    export ED_MOCK_DIR
    ED_MOCK_DIR="$(mktemp -d)"

    # Build the flexible mock docker script
    cat > "$ED_MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_DOCKER_ABSENT:-0}" -ne 0 ]]; then
    echo "bash: docker: command not found" >&2
    exit 127
fi
case "$1" in
    version)
        if [[ "$*" == *GitCommit* ]]; then
            printf '%s\n' "${MOCK_DOCKER_COMMIT:-abc1234}"
        else
            printf '%s\n' "${MOCK_DOCKER_VERSION:-24.0.7}"
        fi
        exit 0
        ;;
    compose)
        if [[ "${MOCK_COMPOSE_ABSENT:-0}" -ne 0 ]]; then
            echo "docker: 'compose' is not a docker command" >&2
            exit 1
        fi
        printf '%s\n' "${MOCK_COMPOSE_VERSION:-2.20.0}"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$ED_MOCK_DIR/docker"

    # Build mock apt-cache script
    cat > "$ED_MOCK_DIR/apt-cache" << 'MOCK'
#!/bin/bash
# MOCK_APT_VERSIONS — space-separated list of versions (newest first)
# Default simulates Docker CE APT repo offering a few versions.
if [[ "$1" == "policy" ]]; then
    versions="${MOCK_APT_VERSIONS:-25.0.3 24.0.9 24.0.7 23.0.6}"
    for v in $versions; do
        printf '   %s\n' "$v"
    done
fi
exit 0
MOCK
    chmod +x "$ED_MOCK_DIR/apt-cache"

    # Build mock apt-get script
    cat > "$ED_MOCK_DIR/apt-get" << 'MOCK'
#!/bin/bash
# MOCK_APT_GET_EXIT — exit code for apt-get install (default: 0)
exit "${MOCK_APT_GET_EXIT:-0}"
MOCK
    chmod +x "$ED_MOCK_DIR/apt-get"

    # Integration: check Docker availability for DinD tests
    export ED_TEST_DOCKER_AVAILABLE=0
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        export ED_TEST_DOCKER_AVAILABLE=1
    fi
}

teardown_file() {
    [[ -d "${ED_MOCK_DIR:-}" ]] && rm -rf "$ED_MOCK_DIR" || true
}

setup() {
    [[ -z "${ED_TESTS_SKIP:-}" ]] || skip "$ED_TESTS_SKIP"
    # Prepend mock dir so cg_guard resolves our stubs at source time
    export PATH="$ED_MOCK_DIR:$PATH"
    # shellcheck source=../config/ensure_docker.sh
    source "$LIB" || return "$ED_TEST_SOURCE_FAILED"
}

# ---------------------------------------------------------------------------
# Source-time checks
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,source,issue-132
@test "ensure_docker.sh sources without error" {
    # Already done in setup; reaching here means source succeeded
    true
}

# bats test_tags=ensure_docker,source,issue-132
@test "all ED_ERR_ constants are defined after sourcing" {
    [[ -n "${ED_ERR_CORRUPT_STATE+x}" ]]          || { echo "ED_ERR_CORRUPT_STATE missing" >&2;          false; }
    [[ -n "${ED_ERR_INSUFFICIENT_PRIVILEGE+x}" ]] || { echo "ED_ERR_INSUFFICIENT_PRIVILEGE missing" >&2; false; }
    [[ -n "${ED_ERR_MISSING_ARGUMENT+x}" ]]       || { echo "ED_ERR_MISSING_ARGUMENT missing" >&2;       false; }
    [[ -n "${ED_ERR_SYNTAX_ERROR+x}" ]]           || { echo "ED_ERR_SYNTAX_ERROR missing" >&2;           false; }
    [[ -n "${ED_ERR_NO_DOCKER+x}" ]]              || { echo "ED_ERR_NO_DOCKER missing" >&2;              false; }
    [[ -n "${ED_ERR_NO_COMPOSE+x}" ]]             || { echo "ED_ERR_NO_COMPOSE missing" >&2;             false; }
    [[ -n "${ED_ERR_WRONG_VERSION+x}" ]]          || { echo "ED_ERR_WRONG_VERSION missing" >&2;          false; }
    [[ -n "${ED_ERR_NO_SUITABLE_VERSION+x}" ]]      || { echo "ED_ERR_NO_SUITABLE_VERSION missing" >&2;      false; }
    [[ -n "${ED_ERR_VERSION_VULNERABLE+x}" ]]     || { echo "ED_ERR_VERSION_VULNERABLE missing" >&2;     false; }
    [[ -n "${ED_ERR_DEPENDENCY_MISSING+x}" ]]     || { echo "ED_ERR_DEPENDENCY_MISSING missing" >&2;     false; }
    [[ -n "${ED_ERR_ALREADY_INSTALLED+x}" ]]      || { echo "ED_ERR_ALREADY_INSTALLED missing" >&2;      false; }
    [[ -n "${ED_ERR_HOST_INCOMPATIBLE+x}" ]]      || { echo "ED_ERR_HOST_INCOMPATIBLE missing" >&2;      false; }
}

# bats test_tags=ensure_docker,source,issue-132
@test "ED_ERR_ numeric values match the approved table" {
    [[ "$ED_ERR_CORRUPT_STATE"          -eq 4  ]]
    [[ "$ED_ERR_INSUFFICIENT_PRIVILEGE" -eq 7  ]]
    [[ "$ED_ERR_MISSING_ARGUMENT"       -eq 8  ]]
    [[ "$ED_ERR_SYNTAX_ERROR"           -eq 9  ]]
    [[ "$ED_ERR_NO_DOCKER"              -eq 13 ]]
    [[ "$ED_ERR_NO_COMPOSE"             -eq 14 ]]
    [[ "$ED_ERR_WRONG_VERSION"          -eq 15 ]]
    [[ "$ED_ERR_NO_SUITABLE_VERSION"      -eq 16 ]]
    [[ "$ED_ERR_VERSION_VULNERABLE"     -eq 17 ]]
    [[ "$ED_ERR_DEPENDENCY_MISSING"     -eq 19 ]]
    [[ "$ED_ERR_ALREADY_INSTALLED"      -eq 20 ]]
    [[ "$ED_ERR_HOST_INCOMPATIBLE"      -eq 21 ]]
}

# bats test_tags=ensure_docker,source,issue-132
@test "Stage 1 entry points are defined after sourcing" {
    [[ "$(type -t ed_has_docker)"       == "function" ]]
    [[ "$(type -t ed_install_docker)"   == "function" ]]
    [[ "$(type -t ed_uninstall_docker)" == "function" ]]
}

# ---------------------------------------------------------------------------
# _ed_semver_compare
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — equal versions returns 0" {
    run _ed_semver_compare "24.0.7" "24.0.7"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — major greater returns 1" {
    run _ed_semver_compare "25.0.0" "24.0.0"
    [[ "$status" -eq 1 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — major lesser returns 2" {
    run _ed_semver_compare "23.0.0" "24.0.0"
    [[ "$status" -eq 2 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — minor greater returns 1" {
    run _ed_semver_compare "24.1.0" "24.0.0"
    [[ "$status" -eq 1 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — minor lesser returns 2" {
    run _ed_semver_compare "24.0.0" "24.1.0"
    [[ "$status" -eq 2 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — patch greater returns 1" {
    run _ed_semver_compare "24.0.8" "24.0.7"
    [[ "$status" -eq 1 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_compare — patch lesser returns 2" {
    run _ed_semver_compare "24.0.6" "24.0.7"
    [[ "$status" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# _ed_semver_satisfies  (constraint satisfaction)
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — ge satisfied" {
    run _ed_semver_satisfies "24.0.7" ">=24.0.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — ge exact boundary satisfied" {
    run _ed_semver_satisfies "24.0.0" ">=24.0.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — ge not satisfied" {
    run _ed_semver_satisfies "23.0.9" ">=24.0.0"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — lt satisfied" {
    run _ed_semver_satisfies "24.0.7" "<25.0.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — lt exact boundary not satisfied" {
    run _ed_semver_satisfies "25.0.0" "<25.0.0"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — combined range satisfied" {
    run _ed_semver_satisfies "24.0.7" ">=24.0.0,<25.0.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — combined range not satisfied — too low" {
    run _ed_semver_satisfies "23.0.9" ">=24.0.0,<25.0.0"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — combined range not satisfied — too high" {
    run _ed_semver_satisfies "25.0.1" ">=24.0.0,<25.0.0"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — exact match =A.B.C satisfied" {
    run _ed_semver_satisfies "24.0.7" "=24.0.7"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — exact match =A.B.C not satisfied" {
    run _ed_semver_satisfies "24.0.8" "=24.0.7"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — shorthand =A.B accepts patch within minor" {
    run _ed_semver_satisfies "24.0.9" "=24.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — shorthand =A.B rejects different minor" {
    run _ed_semver_satisfies "24.1.0" "=24.0"
    [[ "$status" -ne 0 ]]
}

# bats test_tags=ensure_docker,semver,issue-132
@test "_ed_semver_satisfies — bad constraint returns ED_ERR_SYNTAX_ERROR" {
    run _ed_semver_satisfies "24.0.7" ">=bad.version"
    [[ "$status" -eq "$ED_ERR_SYNTAX_ERROR" ]]
}

# ---------------------------------------------------------------------------
# ed_has_docker
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns ED_ERR_NO_DOCKER when docker absent" {
    MOCK_DOCKER_ABSENT=1 run ed_has_docker
    [[ "$status" -eq "$ED_ERR_NO_DOCKER" ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns ED_ERR_NO_COMPOSE when compose absent" {
    MOCK_COMPOSE_ABSENT=1 run ed_has_docker
    [[ "$status" -eq "$ED_ERR_NO_COMPOSE" ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns 0 when docker and compose present no constraint" {
    run ed_has_docker
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns 0 when version satisfies ge constraint" {
    MOCK_DOCKER_VERSION=24.0.7 run ed_has_docker ">=24.0.0"
    [[ "$status" -eq 0 ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns ED_ERR_WRONG_VERSION when version too low" {
    MOCK_DOCKER_VERSION=23.0.9 run ed_has_docker ">=24.0.0"
    [[ "$status" -eq "$ED_ERR_WRONG_VERSION" ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — returns ED_ERR_SYNTAX_ERROR on malformed constraint" {
    run ed_has_docker ">=not-a-version"
    [[ "$status" -eq "$ED_ERR_SYNTAX_ERROR" ]]
}

# bats test_tags=ensure_docker,has_docker,issue-132
@test "ed_has_docker — prints a message to stderr on failure" {
    MOCK_DOCKER_ABSENT=1 run ed_has_docker
    [[ -n "$output" ]]
}

# ---------------------------------------------------------------------------
# ed_install_docker
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — returns ED_ERR_ALREADY_INSTALLED when docker present and no --update" {
    # Docker mock returns 0 for 'docker version' — simulates Docker present.
    # Privilege check must come AFTER the already-installed check so this test
    # works as a non-root user.
    run ed_install_docker
    [[ "$status" -eq "$ED_ERR_ALREADY_INSTALLED" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — returns ED_ERR_INSUFFICIENT_PRIVILEGE when not root and docker absent" {
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "running as root — privilege check cannot be exercised"
    fi
    MOCK_DOCKER_ABSENT=1 run ed_install_docker
    [[ "$status" -eq "$ED_ERR_INSUFFICIENT_PRIVILEGE" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker --update returns ED_ERR_INSUFFICIENT_PRIVILEGE when not root" {
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "running as root — privilege check cannot be exercised"
    fi
    run ed_install_docker --update
    [[ "$status" -eq "$ED_ERR_INSUFFICIENT_PRIVILEGE" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — returns ED_ERR_SYNTAX_ERROR on unknown option" {
    run ed_install_docker --unknown-flag
    [[ "$status" -eq "$ED_ERR_SYNTAX_ERROR" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — returns ED_ERR_NO_SUITABLE_VERSION when no apt candidate matches constraint" {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "requires root to reach version-selection logic"
    fi
    MOCK_DOCKER_ABSENT=1 MOCK_APT_VERSIONS="24.0.7" \
        run ed_install_docker ">=99.0.0"
    [[ "$status" -eq "$ED_ERR_NO_SUITABLE_VERSION" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — returns ED_ERR_HOST_INCOMPATIBLE when apt-get fails for host reasons" {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "requires root to reach apt-get execution"
    fi
    # Simulate: version exists in APT but apt-get install itself fails
    # (e.g. broken dependencies, incompatible OS).
    MOCK_DOCKER_ABSENT=1 MOCK_APT_GET_EXIT=100 \
        run ed_install_docker
    [[ "$status" -eq "$ED_ERR_HOST_INCOMPATIBLE" ]]
}

# bats test_tags=ensure_docker,install_docker,issue-132
@test "ed_install_docker — emits stderr diagnostic on ED_ERR_HOST_INCOMPATIBLE" {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "requires root to reach apt-get execution"
    fi
    MOCK_DOCKER_ABSENT=1 MOCK_APT_GET_EXIT=100 \
        run ed_install_docker
    [[ -n "$output" ]]
}

# ---------------------------------------------------------------------------
# ed_uninstall_docker
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,uninstall_docker,issue-132
@test "ed_uninstall_docker — returns ED_ERR_INSUFFICIENT_PRIVILEGE when not root" {
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "running as root — privilege check cannot be exercised"
    fi
    run ed_uninstall_docker
    [[ "$status" -eq "$ED_ERR_INSUFFICIENT_PRIVILEGE" ]]
}

# ---------------------------------------------------------------------------
# Integration tests — Docker-in-Docker (privileged Ubuntu container)
# ---------------------------------------------------------------------------

# bats test_tags=ensure_docker,integration,issue-132
@test "integration — ed_install_docker installs docker on clean system" {
    if [[ "$ED_TEST_DOCKER_AVAILABLE" -ne 1 ]]; then
        skip "Docker-in-Docker not available"
    fi
    skip "integration fixture not yet set up — Stage 1 implementation task"
}

# bats test_tags=ensure_docker,integration,issue-132
@test "integration — ed_install_docker returns ED_ERR_ALREADY_INSTALLED on second call" {
    if [[ "$ED_TEST_DOCKER_AVAILABLE" -ne 1 ]]; then
        skip "Docker-in-Docker not available"
    fi
    skip "integration fixture not yet set up — Stage 1 implementation task"
}

# bats test_tags=ensure_docker,integration,issue-132
@test "integration — ed_uninstall_docker removes docker and ed_has_docker returns ED_ERR_NO_DOCKER" {
    if [[ "$ED_TEST_DOCKER_AVAILABLE" -ne 1 ]]; then
        skip "Docker-in-Docker not available"
    fi
    skip "integration fixture not yet set up — Stage 1 implementation task"
}

return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #135   | initial preliminary tests — Stage 1 (issue #132)              |
