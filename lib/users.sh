#!/usr/bin/env bash

configure_deploy_user() {
  if id "$DEPLOY_USER" >/dev/null 2>&1; then
    record_skipped "deployment user already exists"
  else
    run useradd --create-home --shell /bin/bash "$DEPLOY_USER"
    record_completed "deployment user created"
  fi
  run usermod -aG docker "$DEPLOY_USER"
  run install -d -m 0750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" -- "$APP_ROOT" "$APP_ROOT/$APP_NAME"
  record_completed "application directory configured"
}
