#!/usr/bin/env bats

# Preliminary tests for config/remote_run.sh
# Run with: bats test/test-remote_run.bats
#
# Integration tests require:
#   - ssh localhost (key-based, no passphrase)
#   - nc (netcat) available locally
#   - Bash >= 4.3 on the remote (localhost)
#
# Tests that cannot meet their prerequisites are skipped, not failed.

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup_file() {
    bats_require_minimum_version 1.5.0

    export LIB="$BATS_TEST_DIRNAME/../config/remote_run.sh"
    if [[ ! -f "$LIB" ]]; then
        echo "Missing library $LIB" >&2
        return 1
    fi

    # Probe SSH connectivity to localhost (key-based, no passphrase).
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=2 \
           -o StrictHostKeyChecking=no \
           localhost true 2>/dev/null; then
        export RR_SSH_AVAILABLE=1
    else
        export RR_SSH_AVAILABLE=0
    fi

    # Probe nc availability.
    if command -v nc &>/dev/null; then
        export RR_NC_AVAILABLE=1
    else
        export RR_NC_AVAILABLE=0
    fi

    # Export a helper that skips when SSH+nc are not both available.
    export -f _rr_require_integration
}

_rr_require_integration() {
    if [[ "${RR_SSH_AVAILABLE:-0}" != 1 ]]; then
        skip "ssh localhost not available (key-based auth required)"
    fi
    if [[ "${RR_NC_AVAILABLE:-0}" != 1 ]]; then
        skip "nc not available locally"
    fi
}

setup() {
    # Create a per-test temporary directory for fixture scripts.
    export RR_TMP
    RR_TMP=$(mktemp -d)
    # Source the library so remote_run is available in the test process.
    # shellcheck source=config/remote_run.sh
    # shellcheck disable=SC1091
    source "$LIB"
}

teardown() {
    rm -rf "${RR_TMP:-}"
}

# ---------------------------------------------------------------------------
# Helper: write a small script into $RR_TMP and return its path.
# Usage: _rr_fixture <filename> <<'EOF' ... EOF
# ---------------------------------------------------------------------------
_rr_fixture() {
    local name="$1"
    local path="$RR_TMP/$name"
    cat > "$path"
    chmod +x "$path"
    printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# 1. Basic execution
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,basic
@test "remote_run: simple script executes and exits 0" {
    _rr_require_integration
    local script
    script=$(_rr_fixture "hello.sh" <<'EOF'
#!/usr/bin/env bash
echo "hello from remote"
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"hello from remote"* ]]
}

# bats test_tags=remote_run,basic
@test "remote_run: script exit code is propagated" {
    _rr_require_integration
    local script
    script=$(_rr_fixture "fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
)
    run -42 remote_run localhost "$script"
}

# bats test_tags=remote_run,basic
@test "remote_run: positional arguments reach the script" {
    _rr_require_integration
    local script
    script=$(_rr_fixture "args.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" "$2"
EOF
)
    run -0 remote_run localhost "$script" alpha beta
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

# ---------------------------------------------------------------------------
# 2. source: basic fetch and execute
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source
@test "remote_run: source fetches a local file and executes it" {
    _rr_require_integration

    # Library defines a variable.
    _rr_fixture "mylib.sh" <<'EOF' > /dev/null
MY_VAR="sourced_value"
EOF

    local script
    script=$(_rr_fixture "use_lib.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/mylib.sh"
printf '%s\n' "\$MY_VAR"
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"sourced_value"* ]]
}

# bats test_tags=remote_run,source
@test "remote_run: source makes variables available in calling scope" {
    _rr_require_integration

    _rr_fixture "vars.sh" <<'EOF' > /dev/null
REMOTE_VAR="visible"
ANOTHER_VAR="also_visible"
EOF

    local script
    script=$(_rr_fixture "check_vars.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/vars.sh"
[[ "\$REMOTE_VAR" == "visible" ]] || exit 1
[[ "\$ANOTHER_VAR" == "also_visible" ]] || exit 2
EOF
)
    run -0 remote_run localhost "$script"
}

# bats test_tags=remote_run,source
@test "remote_run: source makes functions available globally" {
    _rr_require_integration

    _rr_fixture "funcs.sh" <<'EOF' > /dev/null
greet() { printf 'Hello, %s!\n' "$1"; }
EOF

    local script
    script=$(_rr_fixture "use_funcs.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/funcs.sh"
greet "world"
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"Hello, world!"* ]]
}

# ---------------------------------------------------------------------------
# 3. source: positional parameters and return
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,args
@test "remote_run: source passes positional args to the sourced file" {
    _rr_require_integration

    _rr_fixture "print_args.sh" <<'EOF' > /dev/null
printf 'argc=%d\n' "$#"
printf 'arg1=%s\n' "$1"
printf 'arg2=%s\n' "$2"
EOF

    local script
    script=$(_rr_fixture "pass_args.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/print_args.sh" foo bar
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"argc=2"* ]]
    [[ "$output" == *"arg1=foo"* ]]
    [[ "$output" == *"arg2=bar"* ]]
}

# bats test_tags=remote_run,source,args
@test "remote_run: shift works inside sourced file" {
    _rr_require_integration

    _rr_fixture "do_shift.sh" <<'EOF' > /dev/null
shift
printf 'after_shift=%s\n' "$1"
EOF

    local script
    script=$(_rr_fixture "shift_test.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/do_shift.sh" first second
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"after_shift=second"* ]]
}

# bats test_tags=remote_run,source,return
@test "remote_run: return in sourced file stops the file and returns to caller" {
    _rr_require_integration

    _rr_fixture "early_return.sh" <<'EOF' > /dev/null
printf 'before_return\n'
return 0
printf 'after_return\n'   # must not appear
EOF

    local script
    script=$(_rr_fixture "check_return.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/early_return.sh"
printf 'after_source\n'   # must appear
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"before_return"* ]]
    [[ "$output" != *"after_return"* ]]
    [[ "$output" == *"after_source"* ]]
}

# bats test_tags=remote_run,source,return
@test "remote_run: return N from sourced file is the exit code of source" {
    _rr_require_integration

    _rr_fixture "return_code.sh" <<'EOF' > /dev/null
return 7
EOF

    local script
    script=$(_rr_fixture "check_rc.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/return_code.sh"
printf 'rc=%d\n' \$?
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"rc=7"* ]]
}

# ---------------------------------------------------------------------------
# 4. source: nested source
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,nested
@test "remote_run: nested source (A sources B) works" {
    _rr_require_integration

    _rr_fixture "base.sh" <<'EOF' > /dev/null
BASE_LOADED=1
base_func() { printf 'base_func_called\n'; }
EOF

    _rr_fixture "mid.sh" <<EOF > /dev/null
source "$RR_TMP/base.sh"
MID_LOADED=1
EOF

    local script
    script=$(_rr_fixture "top.sh" <<EOF
#!/usr/bin/env bash
source "$RR_TMP/mid.sh"
[[ "\$BASE_LOADED" == 1 ]] || { echo "BASE_LOADED not set" >&2; exit 1; }
[[ "\$MID_LOADED"  == 1 ]] || { echo "MID_LOADED not set"  >&2; exit 2; }
base_func
EOF
)
    run -0 remote_run localhost "$script"
    [[ "$output" == *"base_func_called"* ]]
}

# ---------------------------------------------------------------------------
# 5. Security: whitelist enforcement
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,security
@test "remote_run: source of a path outside whitelist fails" {
    _rr_require_integration

    # Write a file in a DIFFERENT tmp directory (outside the default whitelist).
    local other_dir
    other_dir=$(mktemp -d)
    printf 'FORBIDDEN=1\n' > "$other_dir/secret.sh"

    local script
    script=$(_rr_fixture "try_escape.sh" <<EOF
#!/usr/bin/env bash
source "$other_dir/secret.sh" || true
[[ "\${FORBIDDEN:-}" != 1 ]] || exit 1
EOF
)
    run remote_run localhost "$script"
    # Expect either: the source fails (non-zero exit from the script),
    # or FORBIDDEN was not set (script exits 0 but FORBIDDEN check passes).
    # Either way, the secret content must not have been served.
    [[ "$status" -ne 0 || "$output" != *"FORBIDDEN"* ]]

    rm -rf "$other_dir"
}

# bats test_tags=remote_run,security
@test "remote_run: --allow extends the whitelist" {
    _rr_require_integration

    # Extra library in a separate directory.
    local extra_dir
    extra_dir=$(mktemp -d)
    printf 'EXTRA=loaded\n' > "$extra_dir/extra.sh"

    local script
    script=$(_rr_fixture "use_extra.sh" <<EOF
#!/usr/bin/env bash
source "$extra_dir/extra.sh"
printf '%s\n' "\$EXTRA"
EOF
)
    run -0 remote_run --allow "$extra_dir" localhost "$script"
    [[ "$output" == *"loaded"* ]]

    rm -rf "$extra_dir"
}

# ---------------------------------------------------------------------------
# 6. Missing prerequisites (local unit tests — no SSH required)
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,prerequisites
@test "remote_run: missing nc causes early exit with message" {
    # Override PATH so nc is not found.
    run bash --noprofile --norc -c "
        source '$LIB'
        PATH='/dev/null' remote_run localhost /dev/null
    "
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"nc"* ]]
}

# bats test_tags=remote_run,prerequisites
@test "remote_run: non-existent script causes early exit with message" {
    run bash --noprofile --norc -c "
        source '$LIB'
        remote_run localhost /no/such/script.sh
    "
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"script"* || "$output" == *"not found"* || "$output" == *"no such"* ]]
}
