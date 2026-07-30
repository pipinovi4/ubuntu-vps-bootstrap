#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

CONFIG_FILE="$SCRIPT_DIR/.env"
NO_BUILD=false

usage() {
  cat <<'EOF'
Usage: ./deploy.sh [options]
  --config PATH  Read restricted KEY=value configuration (default: .env)
  --dry-run      Print intended actions
  --verbose      Enable debug logging
  --no-build     Do not build Compose services
  --help         Show this help
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --dry-run) DRY_RUN=true ;;
      --verbose) VERBOSE=true ;;
      --no-build) NO_BUILD=true ;;
      --config)
        (($# >= 2)) || die "--config requires a path"
        CONFIG_FILE="$2"
        shift
        ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

acquire_deploy_lock() {
  local lock_file="$1"
  exec 9>"$lock_file"
  flock -n 9 || die "Another deployment is already running"
}

prepare_repository() {
  local app_dir="$1"
  if [[ ! -d "$app_dir/.git" ]]; then
    [[ -n "$GIT_REPOSITORY" ]] || die "GIT_REPOSITORY is required when the application is not cloned"
    [[ ! -e "$app_dir" || -z "$(find "$app_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      die "Refusing to clone into a non-empty, non-Git directory: $app_dir"
    run_cmd git clone --branch "$GIT_BRANCH" --single-branch -- "$GIT_REPOSITORY" "$app_dir"
  else
    run_cmd git -C "$app_dir" fetch --prune origin
    run_cmd git -C "$app_dir" checkout "$GIT_BRANCH"
    run_cmd git -C "$app_dir" pull --ff-only origin "$GIT_BRANCH"
  fi
}

wait_for_health() {
  local app_dir="$1" attempt
  [[ -n "$HEALTHCHECK_URL" ]] || {
    warn "HEALTHCHECK_URL is empty; skipping health check"
    return 0
  }
  for ((attempt = 1; attempt <= HEALTHCHECK_ATTEMPTS; attempt++)); do
    if curl --fail --silent --show-error --max-time 5 "$HEALTHCHECK_URL" >/dev/null; then
      success "Health check passed"
      return 0
    fi
    sleep "$HEALTHCHECK_INTERVAL_SECONDS"
  done
  log ERROR "Health check failed after $HEALTHCHECK_ATTEMPTS attempts"
  docker compose --project-directory "$app_dir" logs --tail=100 >&2
  return 1
}

write_metadata() {
  local app_dir="$1" commit timestamp temp
  commit="$(git -C "$app_dir" rev-parse HEAD)"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  temp="$(mktemp "$app_dir/.deploy-metadata.XXXXXX")"
  jq -n --arg commit "$commit" --arg branch "$GIT_BRANCH" --arg deployed_at "$timestamp" \
    '{commit:$commit, branch:$branch, deployed_at:$deployed_at}' >"$temp"
  chmod 0644 "$temp"
  mv -f -- "$temp" "$app_dir/deploy-metadata.json"
  printf 'Deployed commit %s from %s at %s\n' "$commit" "$GIT_BRANCH" "$timestamp"
}

main() {
  parse_args "$@"
  load_config "$CONFIG_FILE"
  validate_config
  ((EUID != 0)) || die "Deployment must run as $DEPLOY_USER, not root"
  [[ "$(id -un)" == "$DEPLOY_USER" ]] || die "Deployment must run as configured user: $DEPLOY_USER"
  require_command git
  require_command docker
  require_command flock
  require_command curl
  require_command jq
  local app_dir="$APP_ROOT/$APP_NAME" lock_file="$APP_ROOT/.${APP_NAME}.deploy.lock"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry-run: would acquire lock $lock_file"
  else
    mkdir -p -- "$APP_ROOT"
    acquire_deploy_lock "$lock_file"
  fi
  prepare_repository "$app_dir"
  run_cmd docker compose --project-directory "$app_dir" config --quiet
  run_cmd docker compose --project-directory "$app_dir" pull
  [[ "$NO_BUILD" == "true" ]] || run_cmd docker compose --project-directory "$app_dir" build
  run_cmd docker compose --project-directory "$app_dir" up -d --remove-orphans
  if [[ "$DRY_RUN" == "true" ]]; then
    log DRY-RUN "wait for health check at $HEALTHCHECK_URL and write deployment metadata"
  else
    wait_for_health "$app_dir"
    write_metadata "$app_dir"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
