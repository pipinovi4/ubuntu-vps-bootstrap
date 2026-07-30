#!/usr/bin/env bash

readonly TOOLKIT_NAME="ubuntu-vps-bootstrap"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
declare -a COMPLETED_STEPS=()
declare -a SKIPPED_STEPS=()
declare -a WARNINGS=()

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*" >&2
}
info() { log INFO "$@"; }
warn() {
  WARNINGS+=("$*")
  log WARN "$@"
}
success() { log SUCCESS "$@"; }
debug() { [[ "$VERBOSE" == "true" ]] && log DEBUG "$@" || :; }
die() {
  log ERROR "$*"
  return 1
}

on_error() {
  local status="$1" line="$2" command="$3"
  log ERROR "Command failed (status=${status}, line=${line}): ${command}"
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  debug "Running: $(printf '%q ' "$@")"
  "$@"
}

record_completed() {
  COMPLETED_STEPS+=("$1")
  success "$1"
}
record_skipped() {
  SKIPPED_STEPS+=("$1")
  info "Skipped: $1"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
require_command() { command_exists "$1" || die "Required command not found: $1"; }

backup_file() {
  local path="$1" backup
  [[ -e "$path" ]] || return 0
  backup="${path}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  run cp --preserve=mode,ownership,timestamps -- "$path" "$backup"
}

install_if_changed() {
  local source="$1" target="$2" mode="${3:-0644}" owner="${4:-root}" group="${5:-root}"
  if [[ -f "$target" ]] && cmp -s -- "$source" "$target"; then
    record_skipped "$target is already current"
    return 0
  fi
  backup_file "$target"
  run install -D -m "$mode" -o "$owner" -g "$group" -- "$source" "${target}.tmp"
  run mv -f -- "${target}.tmp" "$target"
}

join_by() {
  local separator="$1"
  shift
  local first=true item
  for item in "$@"; do
    if [[ "$first" == "true" ]]; then first=false; else printf '%s' "$separator"; fi
    printf '%s' "$item"
  done
}
