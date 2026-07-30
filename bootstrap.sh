#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/docker.sh
source "$SCRIPT_DIR/lib/docker.sh"
# shellcheck source=lib/users.sh
source "$SCRIPT_DIR/lib/users.sh"
# shellcheck source=lib/firewall.sh
source "$SCRIPT_DIR/lib/firewall.sh"
# shellcheck source=lib/security.sh
source "$SCRIPT_DIR/lib/security.sh"

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
ORIGINAL_ARGS=("$@")
CONFIG_FILE="$SCRIPT_DIR/.env"
HARDEN_SSH_CLI=false
SKIP_UPGRADE_CLI=false

usage() {
  cat <<'EOF'
Usage: sudo ./bootstrap.sh [options]
  --config PATH   Read restricted KEY=value configuration (default: .env)
  --dry-run       Print intended actions without changing the system
  --verbose       Enable debug logging
  --harden-ssh    Explicitly request conservative SSH hardening
  --skip-upgrade  Disable package upgrades regardless of configuration
  --help          Show this help
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
      --harden-ssh) HARDEN_SSH_CLI=true ;;
      --skip-upgrade) SKIP_UPGRADE_CLI=true ;;
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

print_summary() {
  local docker_version="not installed" compose_version="not installed" firewall_status="not available" swap_status="inactive"
  if command_exists docker; then
    docker_version="$(docker --version 2>/dev/null || printf unavailable)"
    compose_version="$(docker compose version 2>/dev/null || printf unavailable)"
  fi
  command_exists ufw && firewall_status="$(ufw status 2>/dev/null | head -n1 || printf unavailable)"
  command_exists swapon && [[ -n "$(swapon --show=NAME --noheadings 2>/dev/null)" ]] && swap_status="active"
  printf '\n=== Bootstrap summary ===\n'
  printf 'Completed: %s\n' "$(join_by '; ' "${COMPLETED_STEPS[@]:-none}")"
  printf 'Skipped: %s\n' "$(join_by '; ' "${SKIPPED_STEPS[@]:-none}")"
  printf 'Warnings: %s\n' "$(join_by '; ' "${WARNINGS[@]:-none}")"
  printf 'Docker: %s\nCompose: %s\nFirewall: %s\nSwap: %s\n' "$docker_version" "$compose_version" "$firewall_status" "$swap_status"
  printf 'Application directory: %s/%s\nDeployment user: %s\n' "$APP_ROOT" "$APP_NAME" "$DEPLOY_USER"
}

main() {
  parse_args "$@"
  if [[ -f "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE"
  else
    warn "Configuration file not found; using safe defaults: $CONFIG_FILE"
  fi
  [[ "$HARDEN_SSH_CLI" == "true" ]] && ENABLE_SSH_HARDENING=true
  [[ "$SKIP_UPGRADE_CLI" == "true" ]] && ENABLE_SYSTEM_UPGRADE=false
  validate_config
  ensure_root
  if [[ "$DRY_RUN" != "true" ]]; then validate_platform; else info "Dry-run: platform validation deferred"; fi
  install_packages
  install_docker
  configure_deploy_user
  configure_firewall
  configure_fail2ban
  configure_unattended_upgrades
  configure_swap
  configure_sysctl
  configure_logrotate
  configure_ssh_hardening
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
