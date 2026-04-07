#!/usr/bin/env bats

# Preliminary tests for config/remote_run.sh
# Run with: bats test/test-remote_run.bats
#
# Integration tests spin up a Docker container (Alpine + openssh-server) with
# an ephemeral ed25519 key pair.  They are skipped when Docker is unavailable
# or the container fails to start.  Local (no-SSH) tests always run and only
# require the library file to exist.

# ---------------------------------------------------------------------------
# setup_file — start the SSH test container
# ---------------------------------------------------------------------------

setup_file() {
    bats_require_minimum_version 1.5.0

    export LIB="$BATS_TEST_DIRNAME/../config/remote_run.sh"
    if [[ ! -f "$LIB" ]]; then
        echo "Missing library $LIB" >&2
        return 1
    fi

    export RR_DOCKER_AVAILABLE=0

    # Check Docker daemon
    command -v docker &>/dev/null || return 0
    docker info &>/dev/null 2>&1  || return 0

    # Generate an ephemeral ed25519 key pair (no passphrase)
    export RR_KEY_DIR="$BATS_FILE_TMPDIR/ssh"
    mkdir -p "$RR_KEY_DIR"
    ssh-keygen -t ed25519 -f "$RR_KEY_DIR/id_ed25519" -N "" -q || return 0

    # Unique container name for this test run
    export RR_CONTAINER="rr-test-$$"

    # Start Alpine with openssh-server; mount the public key as authorized_keys.
    docker run -d \
        --name "$RR_CONTAINER" \
        -p 0:22 \
        -v "$RR_KEY_DIR/id_ed25519.pub:/root/.ssh/authorized_keys:ro" \
        alpine:latest \
        /bin/sh -c '
            apk add --no-cache --quiet openssh-server bash 2>/dev/null &&
            ssh-keygen -A -q &&
            chmod 700 /root/.ssh &&
            chmod 600 /root/.ssh/authorized_keys &&
            sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config &&
            sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config &&
            exec /usr/sbin/sshd -D -e 2>&1
        ' >/dev/null 2>&1 || return 0

    # Resolve the host port assigned to container port 22
    local port attempts=30
    while [[ $attempts -gt 0 ]]; do
        port=$(docker port "$RR_CONTAINER" 22/tcp 2>/dev/null | head -1 | sed 's/.*://')
        [[ -n "$port" ]] && break
        sleep 1
        (( attempts-- ))
    done
    if [[ -z "${port:-}" ]]; then
        docker rm -f "$RR_CONTAINER" >/dev/null 2>&1; return 0
    fi
    export RR_SSH_PORT="$port"

    # Wait for sshd to accept connections (max 30 s)
    attempts=30
    while [[ $attempts -gt 0 ]]; do
        ssh -o BatchMode=yes \
            -o ConnectTimeout=2 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i "$RR_KEY_DIR/id_ed25519" \
            -p "$RR_SSH_PORT" \
            root@127.0.0.1 true 2>/dev/null && break
        sleep 1
        (( attempts-- ))
    done
    if [[ $attempts -eq 0 ]]; then
        docker logs "$RR_CONTAINER" >&2 2>/dev/null
        docker rm -f "$RR_CONTAINER" >/dev/null 2>&1; return 0
    fi

    export RR_SSH_TARGET="root@127.0.0.1"
    export RR_DOCKER_AVAILABLE=1
}

teardown_file() {
    docker rm -f "${RR_CONTAINER:-}" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Per-test setup / teardown
# ---------------------------------------------------------------------------

setup() {
    export RR_TMP
    RR_TMP=$(mktemp -d)
    # shellcheck source=config/remote_run.sh
    # shellcheck disable=SC1091
    source "$LIB"
}

teardown() {
    rm -rf "${RR_TMP:-}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Skip when the Docker SSH container is not available.
_rr_require_docker() {
    if [[ "${RR_DOCKER_AVAILABLE:-0}" != 1 ]]; then
        skip "Docker SSH container not available"
    fi
}

# Invoke remote_run with the test container's SSH options pre-filled.
_rr() {
    remote_run \
        --ssh-opt "-p ${RR_SSH_PORT}" \
        --ssh-opt "-i ${RR_KEY_DIR}/id_ed25519" \
        --ssh-opt "-o StrictHostKeyChecking=no" \
        --ssh-opt "-o UserKnownHostsFile=/dev/null" \
        "$@"
}

# Write a fixture script from stdin into $RR_TMP/<name>; print its path.
# Usage:
#   script=$(_rr_fixture name.sh <<'EOF'
#   #!/usr/bin/env bash
#   ...
#   EOF)
_rr_fixture() {
    local path="$RR_TMP/$1"
    cat > "$path"
    printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# 1. Basic execution
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,basic
@test "remote_run: simple script executes and exits 0" {
    _rr_require_docker
    local script
    script=$(_rr_fixture hello.sh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "hello from remote"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"hello from remote"* ]]
}

# bats test_tags=remote_run,basic
@test "remote_run: script exit code is propagated" {
    _rr_require_docker
    local script
    script=$(_rr_fixture fail.sh <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
)
    run -42 _rr "$RR_SSH_TARGET" "$script"
}

# bats test_tags=remote_run,basic
@test "remote_run: positional arguments reach the script" {
    _rr_require_docker
    local script
    script=$(_rr_fixture args.sh <<'EOF'
#!/usr/bin/env bash
printf 'arg1=%s\n' "$1"
printf 'arg2=%s\n' "$2"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script" alpha beta
    [[ "$output" == *"arg1=alpha"* ]]
    [[ "$output" == *"arg2=beta"* ]]
}

# ---------------------------------------------------------------------------
# 2. source: basic fetch and execute
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source
@test "remote_run: source fetches a local file and sets variables" {
    _rr_require_docker

    _rr_fixture mylib.sh <<'EOF' > /dev/null
MY_VAR="sourced_value"
EOF

    local script
    # $RR_TMP must expand here; $MY_VAR must remain literal in the script.
    script=$(_rr_fixture use_lib.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/mylib.sh
printf '%s\n' "\$MY_VAR"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"sourced_value"* ]]
}

# bats test_tags=remote_run,source
@test "remote_run: source makes variables visible in calling scope" {
    _rr_require_docker

    _rr_fixture vars.sh <<'EOF' > /dev/null
REMOTE_VAR="visible"
ANOTHER="also_visible"
EOF

    local script
    script=$(_rr_fixture check_vars.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/vars.sh
[[ "\$REMOTE_VAR" == "visible"      ]] || exit 1
[[ "\$ANOTHER"    == "also_visible" ]] || exit 2
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
}

# bats test_tags=remote_run,source
@test "remote_run: source makes functions available globally" {
    _rr_require_docker

    _rr_fixture funcs.sh <<'EOF' > /dev/null
greet() { printf 'Hello, %s!\n' "$1"; }
EOF

    local script
    script=$(_rr_fixture use_funcs.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/funcs.sh
greet "world"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"Hello, world!"* ]]
}

# ---------------------------------------------------------------------------
# 3. source: positional parameters and return
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,args
@test "remote_run: source passes positional args to the sourced file" {
    _rr_require_docker

    _rr_fixture print_args.sh <<'EOF' > /dev/null
printf 'argc=%d\n' "$#"
printf 'arg1=%s\n' "$1"
printf 'arg2=%s\n' "$2"
EOF

    local script
    script=$(_rr_fixture pass_args.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/print_args.sh foo bar
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"argc=2"* ]]
    [[ "$output" == *"arg1=foo"* ]]
    [[ "$output" == *"arg2=bar"* ]]
}

# bats test_tags=remote_run,source,args
@test "remote_run: shift inside sourced file works" {
    _rr_require_docker

    _rr_fixture do_shift.sh <<'EOF' > /dev/null
shift
printf 'after_shift=%s\n' "$1"
EOF

    local script
    script=$(_rr_fixture shift_test.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/do_shift.sh first second
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"after_shift=second"* ]]
}

# bats test_tags=remote_run,source,return
@test "remote_run: return in sourced file stops it and resumes caller" {
    _rr_require_docker

    _rr_fixture early_return.sh <<'EOF' > /dev/null
printf 'before_return\n'
return 0
printf 'after_return\n'
EOF

    local script
    script=$(_rr_fixture check_return.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/early_return.sh
printf 'after_source\n'
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"before_return"* ]]
    [[ "$output" != *"after_return"*  ]]
    [[ "$output" == *"after_source"*  ]]
}

# bats test_tags=remote_run,source,return
@test "remote_run: return N is the exit code of source" {
    _rr_require_docker

    _rr_fixture return_code.sh <<'EOF' > /dev/null
return 7
EOF

    local script
    script=$(_rr_fixture check_rc.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/return_code.sh
printf 'rc=%d\n' "\$?"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"rc=7"* ]]
}

# ---------------------------------------------------------------------------
# 4. Nested source
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,nested
@test "remote_run: nested source (A sources B) works" {
    _rr_require_docker

    _rr_fixture base.sh <<'EOF' > /dev/null
BASE_LOADED=1
base_func() { printf 'base_func_called\n'; }
EOF

    _rr_fixture mid.sh <<EOF > /dev/null
source $RR_TMP/base.sh
MID_LOADED=1
EOF

    local script
    script=$(_rr_fixture top.sh <<EOF
#!/usr/bin/env bash
source $RR_TMP/mid.sh
[[ "\$BASE_LOADED" == 1 ]] || { printf 'BASE_LOADED not set\n' >&2; exit 1; }
[[ "\$MID_LOADED"  == 1 ]] || { printf 'MID_LOADED not set\n'  >&2; exit 2; }
base_func
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"base_func_called"* ]]
}

# ---------------------------------------------------------------------------
# 5. Security: whitelist enforcement
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,security
@test "remote_run: source of a path outside whitelist is rejected" {
    _rr_require_docker

    local other_dir
    other_dir=$(mktemp -d)
    printf 'FORBIDDEN=1\n' > "$other_dir/secret.sh"

    local script
    script=$(_rr_fixture try_escape.sh <<EOF
#!/usr/bin/env bash
source $other_dir/secret.sh || true
[[ "\${FORBIDDEN:-}" != 1 ]] || exit 1
EOF
)
    # Either the source fails (non-zero) or FORBIDDEN is never set (exit 0).
    run _rr "$RR_SSH_TARGET" "$script"
    [[ "$status" -ne 0 || "$output" != *"FORBIDDEN"* ]]

    rm -rf "$other_dir"
}

# bats test_tags=remote_run,security
@test "remote_run: --allow extends the whitelist to an extra directory" {
    _rr_require_docker

    local extra_dir
    extra_dir=$(mktemp -d)
    printf 'EXTRA=loaded\n' > "$extra_dir/extra.sh"

    local script
    script=$(_rr_fixture use_extra.sh <<EOF
#!/usr/bin/env bash
source $extra_dir/extra.sh
printf '%s\n' "\$EXTRA"
EOF
)
    run -0 _rr --allow "$extra_dir" "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"loaded"* ]]

    rm -rf "$extra_dir"
}

# ---------------------------------------------------------------------------
# 6. Local prerequisite checks (no Docker required)
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,prerequisites
@test "remote_run: missing nc causes early exit with an error message" {
    run bash --noprofile --norc -c "
        source '$LIB'
        PATH=/dev/null remote_run user@host /dev/null
    "
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"nc"* ]]
}

# bats test_tags=remote_run,prerequisites
@test "remote_run: non-existent script causes early exit with an error message" {
    run bash --noprofile --norc -c "
        source '$LIB'
        remote_run user@host /no/such/script.sh
    "
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"/no/such/script.sh"* || "$output" == *"not found"* ]]
}
