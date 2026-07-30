#!/usr/bin/env bash

configure_firewall() {
  [[ "$ENABLE_UFW" == "true" ]] || {
    record_skipped "UFW disabled by configuration"
    return
  }
  # Preserve both configured and observed SSH ports before enabling.
  run ufw allow OpenSSH
  run ufw allow "${SSH_PORT}/tcp"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local active_port
    active_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
    if is_port "$active_port"; then run ufw allow "${active_port}/tcp"; fi
  fi
  run ufw allow 80/tcp
  run ufw allow 443/tcp
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw --force enable
  record_completed "UFW configured and enabled"
}
