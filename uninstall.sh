#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: sudo ./uninstall.sh [--dry-run] [--yes] [--help]
Removes only toolkit-managed fail2ban, SSH, sysctl, and logrotate files.
It does NOT remove users, application data, repositories, SSH keys, Docker,
images, containers, volumes, packages, UFW rules, swap, or user home folders.
EOF
}

main() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --yes) ASSUME_YES=true ;;
      --help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
  ((EUID == 0)) || die "Run uninstall with sudo"
  usage
  if [[ "$ASSUME_YES" != "true" ]]; then
    printf 'Type "remove managed configuration" to continue: '
    read -r confirmation
    [[ "$confirmation" == "remove managed configuration" ]] || die "Confirmation did not match; nothing removed"
  fi
  local -a files=(
    /etc/fail2ban/jail.d/ubuntu-vps-bootstrap.local
    /etc/ssh/sshd_config.d/99-ubuntu-vps-bootstrap.conf
    /etc/sysctl.d/99-ubuntu-vps-bootstrap.conf
    /etc/logrotate.d/ubuntu-vps-bootstrap
  )
  local file
  for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then run rm -- "$file"; else record_skipped "$file does not exist"; fi
  done
  if [[ "$DRY_RUN" != "true" ]]; then
    command_exists sshd && sshd -t
    command_exists systemctl && systemctl reload ssh
    command_exists sysctl && sysctl --system
    command_exists systemctl && systemctl restart fail2ban
  fi
  success "Managed configuration removal complete"
}

main "$@"
