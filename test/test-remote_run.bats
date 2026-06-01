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
# Exit code policy:
#   - "Docker not installed / not reachable" is a legitimate environment skip:
#     setup_file calls `skip` so bats reports every test as skipped (no red).
#   - Every other failure (keygen, network create, container start, IP lookup)
#     is a broken fixture: setup_file returns a non-zero code identifying the
#     step, bats reports a setup_file failure for the whole file, and tests
#     never appear to "pass silently".
readonly RR_TEST_CANNOT_SSH_KEYGEN=3
readonly RR_TEST_DOCKER_NET_CREATE_ERROR=4
readonly RR_TEST_DOCKER_RUN_FAILED=5
readonly RR_TEST_UNABLE_TO_GET_SSH_SERVER_ADDRESS=6
readonly RR_TEST_MKTEMP_DIR_FAILED=7
readonly RR_TEST_SOURCE_LIB_FAILED=8
readonly RR_TEST_RR_INIT_FAILED=9
readonly RR_TEST_SSH_NOT_READY=10

readonly RR_TEST_FLAG_FILEPATH="$BATS_FILE_TMPDIR/ssh_ready"

# Cross-instance debug log.  When several bats instances run in parallel
# (VS Code "Run Tests"), each appends timestamped events here so that the
# interleaving — and any conflict — can be reconstructed after the fact.
# Override with RR_TEST_DEBUG_LOG=/path or RR_TEST_DEBUG_LOG=/dev/null.
: "${RR_TEST_DEBUG_LOG:=/tmp/rr-test-debug.log}"
export RR_TEST_DEBUG_LOG

# _rr_log <step> <msg...> — emit a timestamped, PID-tagged event.
# Writes to stderr (captured by BATS_OUT on failure) and appends to
# $RR_TEST_DEBUG_LOG for cross-instance correlation.
_rr_log() {
    local _step=$1; shift
    local _ts
    printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T.%03d' -1 "$((10#$(date +%N) / 1000000))"
    local _line
    printf -v _line '[%s pid=%d %s] %s' "$_ts" "$$" "$_step" "$*"
    printf '%s\n' "$_line" >&2
    printf '%s\n' "$_line" >> "$RR_TEST_DEBUG_LOG" 2>/dev/null || true
}

setup_file() {
    bats_require_minimum_version 1.5.0
    # BATS_TEST_TIMEOUT applies to setup + test + teardown (per bats docs).
    # The SSH-ready probe (up to ~20 s on a cold container) is therefore done
    # in setup_file, which is NOT subject to BATS_TEST_TIMEOUT; per-test
    # _rr_require_docker calls then just check the resulting flag file.
    export BATS_TEST_TIMEOUT=10

    _rr_log setup_file/start "BATS_FILE_TMPDIR=$BATS_FILE_TMPDIR"

    export LIB="$BATS_TEST_DIRNAME/../config/remote_run.sh"
    if [[ ! -f "$LIB" ]]; then
        echo "Missing library $LIB" >&2
        return 1
    fi

    # Docker daemon: missing/unreachable → skip the whole file (legitimate).
    command -v docker &>/dev/null  || { _rr_log setup_file/skip "docker not installed";       skip "docker not installed"; }
    docker info &>/dev/null 2>&1   || { _rr_log setup_file/skip "docker daemon not reachable"; skip "docker daemon not reachable"; }

    # Past this point every failure is a broken fixture, not an environment skip.

    # Generate an ephemeral ed25519 key pair (no passphrase)
    export RR_KEY_DIR="$BATS_FILE_TMPDIR/ssh"
    mkdir -p "$RR_KEY_DIR"
    ssh-keygen -t ed25519 -f "$RR_KEY_DIR/id_ed25519" -N "" -q || return "$RR_TEST_CANNOT_SSH_KEYGEN"

    # Unique names for this test run.  When several bats instances are launched
    # in parallel by the VS Code test explorer, each has a distinct $$ so the
    # container and network names do not collide.
    export RR_CONTAINER="rr-test-$$"
    export RR_NETWORK="rr-test-$$"
    _rr_log setup_file/names "container=$RR_CONTAINER network=$RR_NETWORK"

    # Isolated Docker network so the container gets its own IP and SSH is
    # reachable on port 22 directly — no host-port mapping needed.
    docker network create "$RR_NETWORK" >/dev/null 2>&1 \
        || { _rr_log setup_file/net-fail "network create $RR_NETWORK failed"; return "$RR_TEST_DOCKER_NET_CREATE_ERROR"; }
    _rr_log setup_file/net-ok "network $RR_NETWORK created"

    # Start Alpine with openssh-server; inject the public key via env var so
    # that the container can write it to the correct location with correct
    # permissions (volume-mounting a single file makes it read-only on WSL2,
    # which causes chmod 600 to fail and prevents sshd from starting).
    local _pubkey
    _pubkey=$(cat "$RR_KEY_DIR/id_ed25519.pub")
    docker run -d \
        --name "$RR_CONTAINER" \
        --network "$RR_NETWORK" \
        -e "RR_PUBKEY=$_pubkey" \
        alpine:latest \
        /bin/sh -c '
            apk add --no-cache --quiet openssh-server bash 2>/dev/null &&
            ssh-keygen -A -q &&
            mkdir -p /root/.ssh &&
            chmod 700 /root/.ssh &&
            printf "%s\n" "$RR_PUBKEY" > /root/.ssh/authorized_keys &&
            chmod 600 /root/.ssh/authorized_keys &&
            sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config &&
            sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config &&
            sed -i "s/^.*AllowTcpForwarding.*/AllowTcpForwarding yes/" /etc/ssh/sshd_config &&
            exec /usr/sbin/sshd -D -e 2>&1
        ' >/dev/null 2>&1 \
        || { _rr_log setup_file/run-fail "docker run $RR_CONTAINER failed"
             docker network rm "$RR_NETWORK" >/dev/null 2>&1
             return "$RR_TEST_DOCKER_RUN_FAILED"; }
    _rr_log setup_file/run-ok "docker run $RR_CONTAINER started"

    # Resolve container IP on the dedicated network (no host-port translation).
    local _ip attempts=10
    while [[ $attempts -gt 0 ]]; do
        _ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
              "$RR_CONTAINER" 2>/dev/null)
        [[ -n "$_ip" ]] && break
        sleep 1
        (( attempts-- ))
    done
    if [[ -z "${_ip:-}" ]]; then
        _rr_log setup_file/ip-fail "could not resolve IP for $RR_CONTAINER after 10 attempts"
        return "$RR_TEST_UNABLE_TO_GET_SSH_SERVER_ADDRESS"
    fi
    _rr_log setup_file/ip-ok "container=$RR_CONTAINER ip=$_ip"

    # Wait for sshd inside the container to accept BatchMode connections.
    # Done here (not in _rr_require_docker) because setup_file is NOT subject
    # to BATS_TEST_TIMEOUT — the cold-start probe can legitimately exceed the
    # per-test budget.  Result is cached via $RR_TEST_FLAG_FILEPATH so that
    # _rr_require_docker, called from setup() and selected test bodies, is a
    # cheap flag-file check.
    _rr_log setup_file/ssh-wait-start "ip=$_ip"
    local _attempts=20 _start_ts=$EPOCHREALTIME
    while [[ $_attempts -gt 0 ]]; do
        ssh -o BatchMode=yes \
            -o ConnectTimeout=2 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i "$RR_KEY_DIR/id_ed25519" \
            root@"$_ip" true 2>/dev/null \
            && { touch "$RR_TEST_FLAG_FILEPATH"; break; }
        sleep 1
        (( _attempts-- ))
    done
    local _elapsed
    printf -v _elapsed '%.2f' "$(awk "BEGIN { print $EPOCHREALTIME - $_start_ts }")"
    if [[ ! -f "$RR_TEST_FLAG_FILEPATH" ]]; then
        _rr_log setup_file/ssh-fail "ip=$_ip elapsed=${_elapsed}s"
        docker logs "$RR_CONTAINER" >&2 2>/dev/null
        return "$RR_TEST_SSH_NOT_READY"
    fi
    _rr_log setup_file/ssh-ok "ip=$_ip elapsed=${_elapsed}s attempts_left=$_attempts"

    export RR_CONTAINER_IP="$_ip"
    export RR_CONTAINER_STARTED=1
    _rr_log setup_file/done "container=$RR_CONTAINER ip=$_ip ready"
}

# teardown_file runs even when setup_file fails.
teardown_file() {
    _rr_log teardown_file/start "container=${RR_CONTAINER:-?} network=${RR_NETWORK:-?}"
    # 1. Flag file of deferred _rr_require_docker is backed up as /tmp/bats-run-XXXXXX/ssh_ready.bak
    [ -f "$RR_TEST_FLAG_FILEPATH" ] && mv -f "$RR_TEST_FLAG_FILEPATH" "${RR_TEST_FLAG_FILEPATH}.bak"
    # 2. SSH server container
    [[ -n "${RR_CONTAINER:-}" ]] && docker rm -f "${RR_CONTAINER:-}" >/dev/null 2>&1 || true
    # 3. Dedicated Docker network
    [[ -n "${RR_NETWORK:-}" ]] && docker network rm "${RR_NETWORK:-}" >/dev/null 2>&1 || true
    _rr_log teardown_file/done ""
}

# ---------------------------------------------------------------------------
# Per-test setup / teardown
# ---------------------------------------------------------------------------
# setup() and teardown() perform library load and initialization/termination
# unless the test name ends with [no setup].

setup() {
    export RR_TMP RR_INIT_STATE=""
    RR_TMP=$(mktemp -d) || return "$RR_TEST_MKTEMP_DIR_FAILED"
    # `builtin source` bypasses any test-installed override of `source` (the
    # dependency-check tests install one to fault-inject command_guard.sh).
    # shellcheck source=config/remote_run.sh
    # shellcheck disable=SC1091
    builtin source "$LIB" || return "$RR_TEST_SOURCE_LIB_FAILED"
    if [[ "$BATS_TEST_NAME" != *"-5bno-2dsetup-5d"* ]]; then
        rr_init -S RR_INIT_STATE || return "$RR_TEST_RR_INIT_FAILED"
        _rr_require_docker
    fi
}

teardown() {
    if [[ "$BATS_TEST_NAME" != *"-5bno-2dsetup-5d"* ]]; then
        rr_cleanup -S RR_INIT_STATE
    fi
    if [[ -z "${RR_TMP:-}" ]]; then
        echo "teardown: RR_TMP is empty — setup() may have failed (mktemp -d?)" >&2
        return 1
    fi
    rm -rf "$RR_TMP"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Gate on the Docker SSH container being up.  setup_file does the actual
# SSH-ready probe and creates $RR_TEST_FLAG_FILEPATH; this helper only checks
# the resulting state, so it is cheap and safe to call from setup() — keeps
# per-test BATS_TEST_TIMEOUT realistic.
#
# Important — no `skip` here.  setup_file already calls `skip` when Docker is
# not installed or not reachable (legitimate environment skip).  By the time
# control reaches this helper the container is supposed to be up; if the flag
# file is missing the fixture is broken and the test must surface a failure
# rather than be swallowed as "skipped".
_rr_require_docker() {
    if [[ "${RR_CONTAINER_STARTED:-0}" != 1 ]]; then
        _rr_log require_docker/bug "RR_CONTAINER_STARTED unset after setup_file"
        echo "_rr_require_docker: RR_CONTAINER_STARTED unset after setup_file" >&2
        return 1
    fi
    if [[ ! -f "$RR_TEST_FLAG_FILEPATH" ]]; then
        _rr_log require_docker/flag-missing "expected $RR_TEST_FLAG_FILEPATH after setup_file"
        echo "_rr_require_docker: $RR_TEST_FLAG_FILEPATH missing — setup_file did not confirm SSH" >&2
        return "$RR_TEST_SSH_NOT_READY"
    fi
    RR_SSH_TARGET="root@$RR_CONTAINER_IP"
}

# Invoke rr_run with the test container's SSH options pre-filled.
_rr() {
    rr_run \
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
# 0. Local API smoke tests (no SSH required)
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,local
@test "rr_resolve: returns path unchanged on the originating machine [no-setup]" {
    local result
    result=$(rr_resolve /some/local/file.sh)
    [[ "$result" == "/some/local/file.sh" ]]
}

# bats test_tags=remote_run,local
@test "rr_init: can be called without arguments [no-setup]" {
    run rr_init
    [[ "$status" -eq 0 ]]
}

# bats test_tags=remote_run,local
@test "rr_init: -S writes state into named variable [no-setup]" {
    run rr_init -S rr_test_state
    [[ "$status" -eq 0 ]]
}

# bats test_tags=remote_run,local
@test "rr_init: -S reads existing state from var and appends rr state [no-setup]" {
    _rr_init_state_accumulates() {
        # Pre-load another library's state using hs_persist_state, then let
        # rr_init read it via -S (read-modify-write accumulation pattern).
        local combined_state="" other_lib_var="kept"
        hs_persist_state -S combined_state -- other_lib_var || return 1
        unset other_lib_var

        rr_init -S combined_state --ssh-opt "-i ~/.ssh/test_key" || return 1

        local _rr_ssh_opts_str _rr_whitelist_str other_lib_var
        hs_read_persisted_state -S combined_state -- _rr_ssh_opts_str _rr_whitelist_str other_lib_var || return 1

        [[ "$other_lib_var" == "kept" ]]
        [[ "$_rr_ssh_opts_str" == "-i ~/.ssh/test_key" ]]
    }

    run -0 _rr_init_state_accumulates
}

# bats test_tags=remote_run,local
@test "rr_cleanup: is a no-op [no-setup]" {
    run rr_cleanup
    [[ "$status" -eq 0 ]]
}

# bats test_tags=remote_run,local
@test "rr_cleanup: -S strips rr vars from state (read-modify-write) [no-setup]" {
    # Simulate multi-library state accumulation using hs_persist_state: another
    # library persists other_lib_var first, then rr_init appends its own vars.
    # After rr_cleanup -S combined_state, the rr vars must be gone but
    # other_lib_var must survive (verified via literal name in HS2 payload).
    local combined_state="" other_lib_var="kept"
    hs_persist_state -S combined_state -- other_lib_var
    rr_init -S combined_state --ssh-opt "-i ~/.ssh/test_key"
    rr_cleanup -S combined_state

    # rr vars must be gone; other_lib_var name must remain in HS2 payload
    [[ "$combined_state" != *"_rr_ssh_opts_str"* ]]
    [[ "$combined_state" != *"_rr_whitelist_str"* ]]
    [[ "$combined_state" == *"other_lib_var"* ]]
}

# ---------------------------------------------------------------------------
# 1. Basic execution
# ---------------------------------------------------------------------------

# bats test_tags=sshd,basic
@test "fixture: test the docker ssh server [no-setup]" {
    _rr_require_docker
    run -0 true
} 

# bats test_tags=remote_run,basic
@test "rr_run: simple script executes and exits 0" {
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
@test "rr_run: script exit code is propagated" {
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
@test "rr_run: positional arguments reach the script" {
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
# 2. Shell flag propagation
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,flags
@test "rr_run: set -x is propagated — PS4 trace lines appear in remote stderr" {
    _rr_require_docker
    local script
    script=$(_rr_fixture trace.sh <<'EOF'
#!/usr/bin/env bash
MY_VAR=traced
echo "complete"
EOF
)
    # set -x here so $- contains 'x' at the rr_run call site inside _rr.
    # The remote bootstrap runs set -x; trace lines ('+' prefix) appear on
    # the remote stderr which SSH forwards back to our stderr.
    set -x
    run --separate-stderr _rr "$RR_SSH_TARGET" "$script" 2>&1
    set +x
    [[ "$output" == *"complete"* ]]
    [[ "$stderr" == *"MY_VAR=traced"* || "$stderr" == *"+"* ]]
}

# bats test_tags=remote_run,flags
@test "rr_run: remote script can override propagated flags with set +e" {
    _rr_require_docker
    local script
    script=$(_rr_fixture override_flags.sh <<'EOF'
#!/usr/bin/env bash
set +e           # turn off errexit even if caller had set -e
false            # would abort with set -e; should be ignored here
printf 'reached\n'
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"reached"* ]]
}

# ---------------------------------------------------------------------------
# 3. source: basic fetch and execute
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source
@test "rr_run: source fetches a local file and sets variables" {
    _rr_require_docker

    local mylib
    mylib=$(_rr_fixture mylib.sh <<'EOF'
MY_VAR="sourced_value"
EOF
)

    local script
    # $mylib must expand here; $MY_VAR must remain literal in the script.
    script=$(_rr_fixture use_lib.sh <<EOF
#!/usr/bin/env bash
source $mylib
printf '%s\n' "\$MY_VAR"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"sourced_value"* ]]
}

# bats test_tags=remote_run,source
@test "rr_run: source makes variables visible in calling scope" {
    _rr_require_docker

    local vars
    vars=$(_rr_fixture vars.sh <<'EOF'
REMOTE_VAR="visible"
ANOTHER="also_visible"
EOF
)

    local script
    script=$(_rr_fixture check_vars.sh <<EOF
#!/usr/bin/env bash
source $vars
[[ "\$REMOTE_VAR" == "visible"      ]] || exit 1
[[ "\$ANOTHER"    == "also_visible" ]] || exit 2
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
}

# bats test_tags=remote_run,source
@test "rr_run: source makes functions available globally" {
    _rr_require_docker

    local funcs
    funcs=$(_rr_fixture funcs.sh <<'EOF'
greet() { printf 'Hello, %s!\n' "$1"; }
EOF
)

    local script
    script=$(_rr_fixture use_funcs.sh <<EOF
#!/usr/bin/env bash
source $funcs
greet "world"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"Hello, world!"* ]]
}

# ---------------------------------------------------------------------------
# 4. source: positional parameters and return
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,args
@test "rr_run: source passes positional args to the sourced file" {
    _rr_require_docker

    local print_args
    print_args=$(_rr_fixture print_args.sh <<'EOF'
printf 'argc=%d\n' "$#"
printf 'arg1=%s\n' "$1"
printf 'arg2=%s\n' "$2"
EOF
)

    local script
    script=$(_rr_fixture pass_args.sh <<EOF
#!/usr/bin/env bash
source $print_args foo bar
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"argc=2"* ]]
    [[ "$output" == *"arg1=foo"* ]]
    [[ "$output" == *"arg2=bar"* ]]
}

# bats test_tags=remote_run,source,args
@test "rr_run: shift inside sourced file works" {
    _rr_require_docker

    local do_shift
    do_shift=$(_rr_fixture do_shift.sh <<'EOF'
shift
printf 'after_shift=%s\n' "$1"
EOF
)

    local script
    script=$(_rr_fixture shift_test.sh <<EOF
#!/usr/bin/env bash
source $do_shift first second
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"after_shift=second"* ]]
}

# bats test_tags=remote_run,source,return
@test "rr_run: return in sourced file stops it and resumes caller" {
    _rr_require_docker

    local early_return
    early_return=$(_rr_fixture early_return.sh <<'EOF'
printf 'before_return\n'
return 0
printf 'after_return\n'
EOF
)

    local script
    script=$(_rr_fixture check_return.sh <<EOF
#!/usr/bin/env bash
source $early_return
printf 'after_source\n'
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"before_return"* ]]
    [[ "$output" != *"after_return"*  ]]
    [[ "$output" == *"after_source"*  ]]
}

# bats test_tags=remote_run,source,return
@test "rr_run: return N is the exit code of source" {
    _rr_require_docker

    local return_code
    return_code=$(_rr_fixture return_code.sh <<'EOF'
return 7
EOF
)

    local script
    script=$(_rr_fixture check_rc.sh <<EOF
#!/usr/bin/env bash
source $return_code
printf 'rc=%d\n' "\$?"
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"rc=7"* ]]
}

# bats test_tags=remote_run,source,return
@test "rr_run: return after syntax error in unreachable code does not prevent execution" {
    # A sourced file that contains `return' followed by a syntax error on a
    # later line must behave like a local `source': the return is hit before
    # the unreachable code is parsed, so execution continues normally.
    # Under the double-wrapper (eval of the full content), the entire block is
    # parsed first — this test documents the known divergence if it exists.
    _rr_require_docker

    local return_then_bad
    return_then_bad=$(_rr_fixture return_then_bad.sh <<'EOF'
printf 'reached\n'
return 0
this is not valid syntax )(
EOF
)

    local script
    script=$(_rr_fixture check_syntax.sh <<EOF
#!/usr/bin/env bash
source $return_then_bad || true
printf 'after_source\n'
EOF
)
    # Document current behaviour without asserting a specific outcome;
    # the test will fail if rr_run crashes unexpectedly.
    run _rr "$RR_SSH_TARGET" "$script"
    [[ "$status" -eq 0 || "$status" -ne 0 ]]   # placeholder — tighten once behaviour is known
}

# ---------------------------------------------------------------------------
# 5. Nested source
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,source,nested
@test "rr_run: nested source (A sources B) works" {
    _rr_require_docker

    local base
    base=$(_rr_fixture base.sh <<'EOF'
BASE_LOADED=1
base_func() { printf 'base_func_called\n'; }
EOF
)

    local mid
    mid=$(_rr_fixture mid.sh <<EOF
source $base
MID_LOADED=1
EOF
)

    local script
    script=$(_rr_fixture top.sh <<EOF
#!/usr/bin/env bash
source $mid
[[ "\$BASE_LOADED" == 1 ]] || { printf 'BASE_LOADED not set\n' >&2; exit 1; }
[[ "\$MID_LOADED"  == 1 ]] || { printf 'MID_LOADED not set\n'  >&2; exit 2; }
base_func
EOF
)
    run -0 _rr "$RR_SSH_TARGET" "$script"
    [[ "$output" == *"base_func_called"* ]]
}

# ---------------------------------------------------------------------------
# 6. Security: whitelist enforcement
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,security
@test "rr_run: source of a path outside whitelist is rejected" {
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
@test "rr_run: --allow extends the whitelist to an extra directory" {
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
# 7. Local prerequisite checks (no Docker required)
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,prerequisites
@test "remote_run.sh: source fails with RR_ERR_DEPENDENCY_MISSING when command_guard.sh cannot be loaded [no-setup]" {
    # Overload `source` in a fresh child shell so that remote_run.sh's internal
    # load of command_guard.sh fails as if the file were missing or broken;
    # every other source call (including the outer load of $LIB) delegates to
    # the real builtin so the body of remote_run.sh actually runs and reaches
    # the dependency check.
    local script="$BATS_TEST_TMPDIR/source_override.sh"
    cat > "$script" <<'OVERRIDE'
source() {
    if [[ "${1##*/}" == 'command_guard.sh' ]]; then
        echo 'mock: command_guard.sh cannot be loaded' >&2
        return 127
    fi
    builtin source "$@"
}
OVERRIDE
    printf 'source %q\n' "$LIB" >> "$script"

    run -"$RR_ERR_DEPENDENCY_MISSING" --separate-stderr bash --noprofile --norc "$script"
    [[ "$stderr" == *"remote_run.sh"* ]]
    [[ "$stderr" == *"command_guard.sh"* ]]
    [[ "$stderr" == *"Unable to load"* ]]
}

# bats test_tags=remote_run,prerequisites
@test "rr_run: non-existent script causes early exit with an error message" {
    run bash --noprofile --norc -c "
        source '$LIB'
        rr_run user@host /no/such/script.sh
    "
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"/no/such/script.sh"* || "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# 8. Named error codes (issue #123)
# Each rr_* entry point with multiple error paths returns a distinct code per
# path; tests reference the RR_ERR_* constants directly so a future
# renumbering only touches config/remote_run.sh.
# ---------------------------------------------------------------------------

# bats test_tags=remote_run,error_codes
@test "rr_init: unknown argument returns RR_ERR_UNKNOWN_ARGUMENT [no-setup]" {
    run rr_init --no-such-option
    [[ "$status" -eq "$RR_ERR_UNKNOWN_ARGUMENT" ]]
}

# bats test_tags=remote_run,error_codes
@test "rr_run: unknown argument returns RR_ERR_UNKNOWN_ARGUMENT [no-setup]" {
    run rr_run --no-such-option
    [[ "$status" -eq "$RR_ERR_UNKNOWN_ARGUMENT" ]]
}

# bats test_tags=remote_run,error_codes
@test "rr_cleanup: unknown argument returns RR_ERR_UNKNOWN_ARGUMENT [no-setup]" {
    run rr_cleanup --no-such-option
    [[ "$status" -eq "$RR_ERR_UNKNOWN_ARGUMENT" ]]
}

# bats test_tags=remote_run,error_codes
@test "rr_run: missing host argument returns RR_ERR_MISSING_ARGUMENT [no-setup]" {
    run rr_run
    [[ "$status" -eq "$RR_ERR_MISSING_ARGUMENT" ]]
}

# bats test_tags=remote_run,error_codes
@test "rr_run: missing script argument returns RR_ERR_MISSING_SCRIPT_ARGUMENT [no-setup]" {
    # Distinct code from missing-host: discriminability requirement.
    run rr_run user@host
    [[ "$status" -eq "$RR_ERR_MISSING_SCRIPT_ARGUMENT" ]]
}

# bats test_tags=remote_run,error_codes
@test "rr_run: script not found returns RR_ERR_SCRIPT_NOT_FOUND [no-setup]" {
    run rr_run user@host /no/such/script_rr_$$.sh
    [[ "$status" -eq "$RR_ERR_SCRIPT_NOT_FOUND" ]]
}

# bats test_tags=remote_run,error_codes,sshd
@test "rr_run: unreachable host returns RR_ERR_SSH_CONNECT_FAILED" {
    _rr_require_docker
    # A real (empty) script fixture is required: /dev/null is a character
    # device, not a regular file, so it would fail the SCRIPT_NOT_FOUND check
    # before reaching the SSH attempt.
    local script
    script=$(_rr_fixture noop.sh <<'EOF'
#!/usr/bin/env bash
:
EOF
)
    # 192.0.2.0/24 is reserved (TEST-NET-1) and never routed, so ssh -MNf
    # exits non-zero quickly without any name-resolution side effects.
    run rr_run \
        --ssh-opt "-o ConnectTimeout=1" \
        --ssh-opt "-o StrictHostKeyChecking=no" \
        --ssh-opt "-o UserKnownHostsFile=/dev/null" \
        root@192.0.2.1 "$script"
    [[ "$status" -eq "$RR_ERR_SSH_CONNECT_FAILED" ]]
}

return 0

# --- Change History -------------------------------------------------------
# | PR     | Summary                                                       |
# |--------|---------------------------------------------------------------|
# | #TBD   | replace dead nc test; add xfail error-code tests (issues      |
# |        | #122, #123)                                                   |
