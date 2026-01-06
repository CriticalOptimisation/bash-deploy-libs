#!/usr/bin/env bats

setup_file() {
  # Define path to remote_access.sh
  export LIB_REMOTE="$BATS_TEST_DIRNAME/../config/remote_access.sh"
  if [ ! -f "$LIB_REMOTE" ]; then
    echo "Missing $LIB_REMOTE" >&2
    return 1
  fi

  # Define hs_cleanup_output helper
  export LIB_STATE="$BATS_TEST_DIRNAME/../config/handle_state.sh"
  if [ ! -f "$LIB_STATE" ]; then
    echo "Missing $LIB_STATE" >&2
    return 1
  fi
  source "$LIB_STATE"  # Automatically calls hs_setup_output_to_stdout
  hs_cleanup_output
  export -f hs_setup_output_to_stdout hs_cleanup_output
}
setup() {
  hs_setup_output_to_stdout
  export -f hs_echo
}
teardown() {
  hs_cleanup_output
}

# Define a helper to create a fake persisted state
make_state() {
  local SSH_AUTH_SOCK="${1-}"
  local SSH_AGENT_PID="${2-}"
  local global_alias_defined="${3-true}"
  local ssh_agent_started="${4-false}"
  hs_persist_state SSH_AUTH_SOCK SSH_AGENT_PID global_alias_defined ssh_agent_started
}
export -f make_state  # makes it available in bash -lc calls

# Normal case
@test "ra_ensure_dns_works_and_host_is_reachable returns 0 for reachable host" {
  run bash -lc '
    # shellcheck source=../config/remote_access.sh
    source "$LIB_REMOTE"
    ra_ensure_dns_works_and_host_is_reachable "localhost"
  '
  [ "$status" -eq 0 ]
}

@test "ra_ensure_dns_works_and_host_is_reachable fails for empty host" {
  run bash -lc '
    # shellcheck source=../config/remote_access.sh
    source "$LIB_REMOTE"
    ra_ensure_dns_works_and_host_is_reachable
  '
  [ "$status" -eq 109 ]  # RA_ERR_MISSING_PARAMETER
  [[ "$output" == *"Usage: ra_ensure_dns_works_and_host_is_reachable <remote_host>"* ]]
} 

@test "ra_ensure_dns_works_and_host_is_reachable fails for unreachable host" {
  run bash -lc '
    # shellcheck source=../config/remote_access.sh
    source "$LIB_REMOTE"
    ra_ensure_dns_works_and_host_is_reachable "nonexistent.invalid.domain"
  '
  [ "$status" -eq 103 ]  # RA_ERR_DNS_FAILURE
  [[ "$output" == *"DNS resolution for nonexistent.invalid.domain failed"* ]]
}

@test "ra_ensure_ssh_access requires a remote host" {
  run bash -lc '
    # shellcheck source=/dev/null
    source "$LIB_REMOTE"
    ra_ensure_ssh_access
    rc=$?
    if type ra_ssh >/dev/null 2>&1; then
      echo "ra_ssh should not be defined"
      rc=99
    fi
    exit "$rc"
  '
  [ "$status" -eq 104 ]  # RA_ERR_HOST_REQUIRED
  [[ "$output" == *"Remote host is required for ensure_ssh_access."* ]]
}

@test "ra_ensure_ssh_access defines ra_ssh alias on success" {
  run bash -lc '
    # shellcheck source=/dev/null
    source "$LIB_REMOTE"
    ra_ensure_ssh_access "localhost" 22 1
    rc=$?
    if ! type ra_ssh >/dev/null 2>&1; then
      echo "ra_ssh not defined"
      rc=95
    fi
    hs_cleanup_output
    exit "$rc"
  '
  [ "$status" -eq 0 ]
}

@test "ra_cleanup_ssh_access stops agent and removes ra_ssh alias when started" {
  run bash -lc '
    tmp="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$tmp"
    cat >"$tmp/ssh-agent" <<EOF
#!/bin/bash
echo "ssh-agent called \$*" >>"$BATS_TEST_TMPDIR/agent_log"
exit 0
EOF
    chmod +x "$tmp/ssh-agent"
    PATH="$tmp:$PATH"
    # shellcheck source=/dev/null
    source "$LIB_REMOTE"
    ra_ssh() { echo "placeholder"; }
    make_state() {
      local SSH_AUTH_SOCK="/tmp/fake.sock"
      local SSH_AGENT_PID=4242
      local global_alias_defined=true
      local ssh_agent_started=true
      hs_persist_state SSH_AUTH_SOCK SSH_AGENT_PID global_alias_defined ssh_agent_started
    }
    state=$(make_state)
    ra_cleanup_ssh_access "$state"
    rc=$?
    agent_log=""
    if [ -f "$BATS_TEST_TMPDIR/agent_log" ]; then
      agent_log=$(cat "$BATS_TEST_TMPDIR/agent_log")
    fi
    if type ra_ssh >/dev/null 2>&1; then
      echo "ra_ssh still defined"
      rc=98
    fi
    hs_cleanup_output
    echo "$agent_log"
    exit "$rc"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "." ]
  [[ "$output" == *"ssh-agent called -k"* ]]
  [[ "$output" == *"Stopped temporary ssh-agent (PID 4242)"* ]]
}
@test "prepare_upload_from_git_state emits guarded code that fails when local is pre-set" {
  run bash -lc '# shellcheck source=/dev/null
source "$LIB_REMOTE"; state=$(prepare_upload_from_git_state current); cleanup(){ local upload_dir="already"; eval "$1"; }; cleanup "$state" 2>&1'
  [ "$status" -ne 0 ]
  [[ "$output" == *"local upload_dir already set in cleanup"* ]]
}

@test "ra_cleanup_ssh_access skips ssh-agent stop when not started" {
  run bash -lc '
    tmp="$BATS_TEST_TMPDIR/fakebin2"
    mkdir -p "$tmp"
    cat >"$tmp/ssh-agent" <<EOF
#!/bin/bash
echo "ssh-agent called \$*" >>"$BATS_TEST_TMPDIR/agent_log_skip"
exit 0
EOF
    chmod +x "$tmp/ssh-agent"
    PATH="$tmp:$PATH"
    # shellcheck source=/dev/null
    source "$LIB_REMOTE"
    ra_ssh() { :; }
    make_state() {
      local SSH_AUTH_SOCK=""
      local SSH_AGENT_PID=""
      local global_alias_defined=true
      local ssh_agent_started=false
      hs_persist_state SSH_AUTH_SOCK SSH_AGENT_PID global_alias_defined ssh_agent_started
    }
    state=$(make_state)
    ra_cleanup_ssh_access "$state"
    rc=$?
    if [ -f "$BATS_TEST_TMPDIR/agent_log_skip" ]; then
      echo "ssh-agent was called unexpectedly"
      rc=97
    fi
    if type ra_ssh >/dev/null 2>&1; then
      echo "ra_ssh still defined"
      rc=96
    fi
    hs_cleanup_output
    exit "$rc"
  '
  [ "$status" -eq 0 ]
}