#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/deploy.sh"
}

@test "deployment lock refuses concurrent holder" {
  local lock="$BATS_TEST_TMPDIR/deploy.lock"
  exec 8>"$lock"
  flock -n 8
  run bash -c "source '$REPO_ROOT/lib/common.sh'; source '$REPO_ROOT/deploy.sh'; acquire_deploy_lock '$lock'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already running"* ]]
}

@test "dry-run constructs safe git clone command" {
  DRY_RUN=true
  GIT_REPOSITORY="https://example.invalid/app.git"
  GIT_BRANCH="main"
  run prepare_repository "$BATS_TEST_TMPDIR/app"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git clone"* ]]
  [[ "$output" == *"--branch main"* ]]
}
