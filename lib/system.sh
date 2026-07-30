#!/usr/bin/env bash

validate_platform() {
  [[ -r /etc/os-release ]] || die "Cannot identify operating system"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required (found ${ID:-unknown})"
  [[ "${VERSION_ID:-}" == "24.04" || "${VERSION_ID:-}" == "22.04" ]] ||
    warn "Ubuntu ${VERSION_ID:-unknown} is not a tested release"
  case "$(dpkg --print-architecture)" in amd64 | arm64) ;; *) die "Unsupported architecture: $(dpkg --print-architecture)" ;; esac
}

ensure_root() {
  ((EUID == 0)) && return 0
  [[ "$DRY_RUN" == "true" ]] && {
    warn "Not root; dry-run will continue without sudo"
    return 0
  }
  command_exists sudo || die "Run as root; sudo is unavailable"
  info "Re-executing with sudo"
  exec sudo --preserve-env=TERM -- "$0" "${ORIGINAL_ARGS[@]}"
}

install_packages() {
  local -a packages=(ca-certificates curl git gnupg jq rsync unzip ufw fail2ban unattended-upgrades)
  run apt-get update
  if [[ "$ENABLE_SYSTEM_UPGRADE" == "true" ]]; then run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; else record_skipped "system package upgrade"; fi
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  record_completed "common packages installed"
}

configure_swap() {
  [[ "$ENABLE_SWAP" == "true" ]] || {
    record_skipped "swap creation disabled"
    return
  }
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q .; then
    record_skipped "swap already active"
    return
  fi
  local swapfile="/swapfile"
  if [[ ! -f "$swapfile" ]]; then
    if command_exists fallocate; then run fallocate -l "${SWAP_SIZE_GB}G" "$swapfile"; else run dd if=/dev/zero of="$swapfile" bs=1M count="$((SWAP_SIZE_GB * 1024))" status=progress; fi
  fi
  run chmod 0600 "$swapfile"
  run mkswap "$swapfile"
  run swapon "$swapfile"
  if ! grep -Eq '^/swapfile[[:space:]]' /etc/fstab; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log DRY-RUN "append /swapfile entry to /etc/fstab"
    else
      local fstab_temp
      fstab_temp="$(mktemp /etc/fstab.XXXXXX)"
      cat /etc/fstab >"$fstab_temp"
      printf '/swapfile none swap sw 0 0\n' >>"$fstab_temp"
      backup_file /etc/fstab
      chmod --reference=/etc/fstab "$fstab_temp"
      chown --reference=/etc/fstab "$fstab_temp"
      mv -f -- "$fstab_temp" /etc/fstab
    fi
  fi
  record_completed "swap configured"
}

configure_sysctl() {
  local rendered
  rendered="$(mktemp)"
  sed "s/{{SWAPPINESS}}/10/g" "$SCRIPT_DIR/templates/sysctl.conf" >"$rendered"
  install_if_changed "$rendered" /etc/sysctl.d/99-ubuntu-vps-bootstrap.conf 0644
  rm -f -- "$rendered"
  run sysctl --system
  record_completed "sysctl settings configured"
}

enable_service() {
  run systemctl enable --now "$1"
}
