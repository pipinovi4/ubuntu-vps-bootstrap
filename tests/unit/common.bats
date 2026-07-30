#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/lib/common.sh"
}

@test "run prints shell-escaped command in dry-run mode" {
  DRY_RUN=true
  run run printf '%s\n' "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
  [[ "$output" == *"hello\\ world"* ]]
}

@test "install_if_changed skips identical files" {
  local source_file="$BATS_TEST_TMPDIR/source" target="$BATS_TEST_TMPDIR/target"
  printf 'same\n' >"$source_file"
  cp "$source_file" "$target"
  run install_if_changed "$source_file" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already current"* ]]
}
