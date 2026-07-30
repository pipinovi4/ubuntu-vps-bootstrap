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

@test "missing default configuration is created with restricted permissions" {
  local example="$BATS_TEST_TMPDIR/example" target="$BATS_TEST_TMPDIR/.env"
  printf 'APP_NAME=my-app\n' >"$example"
  ensure_default_config "$example" "$target"
  [ "$(cat "$target")" = "APP_NAME=my-app" ]
  [ "$(stat -c '%a' "$target")" = "600" ]
}

@test "existing default configuration is never overwritten" {
  local example="$BATS_TEST_TMPDIR/example" target="$BATS_TEST_TMPDIR/.env"
  printf 'APP_NAME=new\n' >"$example"
  printf 'APP_NAME=existing\n' >"$target"
  ensure_default_config "$example" "$target"
  [ "$(cat "$target")" = "APP_NAME=existing" ]
}

@test "dry-run reports configuration creation without writing a file" {
  local example="$BATS_TEST_TMPDIR/example" target="$BATS_TEST_TMPDIR/.env"
  printf 'APP_NAME=my-app\n' >"$example"
  DRY_RUN=true
  run ensure_default_config "$example" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
  [ ! -e "$target" ]
}
