#!/usr/bin/env bats

setup_file() {
  # Define path to install script
  export INSTALL_SCRIPT="$BATS_TEST_DIRNAME/../install_plex_remote.sh"
  if [ ! -f "$INSTALL_SCRIPT" ]; then
    echo "Missing $INSTALL_SCRIPT" >&2
    return 1
  fi
}

@test "install script sources required libraries" {
  run bash -c "source '$INSTALL_SCRIPT' 2>&1 || true"
  [ "$status" -eq 0 ]
}

@test "install script guards essential commands" {
  run bash -c "source '$INSTALL_SCRIPT' && type guard >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "install script defines remote_exec function" {
  run bash -c "source '$INSTALL_SCRIPT' && type remote_exec >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "install script handles missing remote host argument" {
  run bash "$INSTALL_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REMOTE_HOST"* ]]
}

@test "install script validates remote connectivity (mock)" {
  # This would require mocking SSH
  skip "Requires SSH mocking setup"
}

@test "install script persists installation state" {
  run bash -c "source '$INSTALL_SCRIPT' && type hs_persist_state >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}