#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/config.sh"
}

@test "boolean validation accepts only lowercase true and false" {
  is_boolean true
  is_boolean false
  ! is_boolean yes
  ! is_boolean TRUE
}

@test "positive integer validation rejects zero and signs" {
  is_positive_integer 1
  is_positive_integer 42
  ! is_positive_integer 0
  ! is_positive_integer -1
  ! is_positive_integer +2
}

@test "username validation is conservative and rejects root" {
  is_username deploy
  is_username deploy-user
  ! is_username root
  ! is_username "Bad User"
}

@test "port validation enforces valid TCP range" {
  is_port 22
  is_port 65535
  ! is_port 0
  ! is_port 65536
  ! is_port ssh
}

@test "application name validation blocks path traversal" {
  is_app_name my-app
  ! is_app_name ..
  ! is_app_name "my/app"
  ! is_app_name "-bad"
}

@test "safe parser reads values without executing shell" {
  local marker="$BATS_TEST_TMPDIR/executed" config="$BATS_TEST_TMPDIR/config"
  printf 'APP_NAME=demo\nGIT_REPOSITORY=$(touch %s)\n' "$marker" >"$config"
  run load_config "$config"
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
}

@test "safe parser rejects unknown keys" {
  local config="$BATS_TEST_TMPDIR/config"
  printf 'UNKNOWN=value\n' >"$config"
  run load_config "$config"
  [ "$status" -ne 0 ]
}

@test "required configuration validation succeeds for defaults" {
  validate_config
}
