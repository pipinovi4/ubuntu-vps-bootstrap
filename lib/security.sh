#!/usr/bin/env bash

configure_fail2ban() {
  [[ "$ENABLE_FAIL2BAN" == "true" ]] || {
    record_skipped "fail2ban disabled by configuration"
    return
  }
  local rendered
  rendered="$(mktemp)"
  sed "s/{{SSH_PORT}}/$SSH_PORT/g" "$SCRIPT_DIR/templates/fail2ban-jail.local" >"$rendered"
  install_if_changed "$rendered" /etc/fail2ban/jail.d/ubuntu-vps-bootstrap.local 0644
  rm -f -- "$rendered"
  if [[ "$DRY_RUN" != "true" ]]; then fail2ban-client -t; fi
  enable_service fail2ban
  record_completed "fail2ban configured"
}

configure_unattended_upgrades() {
  [[ "$ENABLE_UNATTENDED_UPGRADES" == "true" ]] || {
    record_skipped "unattended upgrades disabled"
    return
  }
  run_cmd env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades
  enable_service unattended-upgrades
  record_completed "automatic security updates enabled"
}

ssh_key_is_safe() {
  local home auth owner mode
  home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  auth="$home/.ssh/authorized_keys"
  [[ -s "$auth" ]] || return 1
  owner="$(stat -c '%U' "$auth")"
  mode="$(stat -c '%a' "$auth")"
  [[ "$owner" == "$DEPLOY_USER" ]] || return 1
  ((8#$mode <= 8#600)) || return 1
  [[ "$(stat -c '%U' "$home/.ssh")" == "$DEPLOY_USER" ]] || return 1
  ((8#$(stat -c '%a' "$home/.ssh") <= 8#700))
}

configure_ssh_hardening() {
  [[ "$ENABLE_SSH_HARDENING" == "true" ]] || {
    record_skipped "SSH hardening not explicitly enabled"
    return
  }
  if ! id "$DEPLOY_USER" >/dev/null 2>&1 || ! ssh_key_is_safe; then
    warn "SSH hardening skipped: deployment user's authorized_keys is absent or unsafe"
    return 0
  fi
  local target=/etc/ssh/sshd_config.d/99-ubuntu-vps-bootstrap.conf rendered previous=""
  rendered="$(mktemp)"
  sed "s/{{SSH_PORT}}/$SSH_PORT/g" "$SCRIPT_DIR/templates/ssh-hardening.conf" >"$rendered"
  if [[ -e "$target" && "$DRY_RUN" != "true" ]]; then
    previous="$(mktemp)"
    cp --preserve=mode,ownership,timestamps -- "$target" "$previous"
  fi
  install_if_changed "$rendered" "$target" 0644
  rm -f -- "$rendered"
  if [[ "$DRY_RUN" != "true" ]]; then
    if ! sshd -t; then
      warn "sshd validation failed; restoring backup and refusing reload"
      if [[ -n "$previous" ]]; then
        install -m 0644 -o root -g root -- "$previous" "${target}.tmp"
        mv -f -- "${target}.tmp" "$target"
      else
        rm -- "$target"
      fi
      rm -f -- "$previous"
      return 1
    fi
    [[ -z "$previous" ]] || rm -f -- "$previous"
  fi
  run_cmd systemctl reload ssh
  record_completed "conservative SSH hardening enabled"
}

configure_logrotate() {
  local content temp target=/etc/logrotate.d/ubuntu-vps-bootstrap
  content="/var/log/ubuntu-vps-bootstrap.log {
    su root adm
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 root adm
}"
  temp="$(mktemp)"
  printf '%s\n' "$content" >"$temp"
  install_if_changed "$temp" "$target" 0644
  rm -f -- "$temp"
  if [[ "$DRY_RUN" != "true" ]]; then logrotate --debug "$target" >/dev/null; fi
  record_completed "toolkit log rotation configured"
}
