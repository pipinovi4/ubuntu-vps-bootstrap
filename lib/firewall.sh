#!/usr/bin/env bash

configure_firewall() {
  [[ "$ENABLE_UFW" == "true" ]] || {
    record_skipped "UFW disabled by configuration"
    return
  }
  # Preserve both configured and observed SSH ports before enabling.
  run_cmd ufw allow OpenSSH
  run_cmd ufw allow "${SSH_PORT}/tcp"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local active_port
    active_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
    if is_port "$active_port"; then run_cmd ufw allow "${active_port}/tcp"; fi
  fi
  run_cmd ufw allow 80/tcp
  run_cmd ufw allow 443/tcp
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw --force enable
  record_completed "UFW configured and enabled"
}
