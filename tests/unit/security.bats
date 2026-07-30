#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT_DIR="$REPO_ROOT"
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/config.sh"
  source "$REPO_ROOT/lib/security.sh"
}

@test "SSH hardening is refused when deployment user is missing" {
  ENABLE_SSH_HARDENING=true
  DEPLOY_USER="definitely_missing_user"
  run configure_ssh_hardening
  [ "$status" -eq 0 ]
  [[ "$output" == *"authorized_keys is absent or unsafe"* ]]
}
