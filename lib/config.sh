#!/usr/bin/env bash

APP_NAME="my-app"
DEPLOY_USER="deploy"
APP_ROOT="/opt/apps"
SSH_PORT="22"
ENABLE_SYSTEM_UPGRADE="false"
ENABLE_SWAP="true"
SWAP_SIZE_GB="2"
ENABLE_UFW="true"
ENABLE_FAIL2BAN="true"
ENABLE_UNATTENDED_UPGRADES="true"
ENABLE_SSH_HARDENING="false"
GIT_REPOSITORY=""
GIT_BRANCH="main"
HEALTHCHECK_URL="http://127.0.0.1/health"
HEALTHCHECK_ATTEMPTS="30"
HEALTHCHECK_INTERVAL_SECONDS="2"

readonly CONFIG_KEYS="APP_NAME DEPLOY_USER APP_ROOT SSH_PORT ENABLE_SYSTEM_UPGRADE ENABLE_SWAP SWAP_SIZE_GB ENABLE_UFW ENABLE_FAIL2BAN ENABLE_UNATTENDED_UPGRADES ENABLE_SSH_HARDENING GIT_REPOSITORY GIT_BRANCH HEALTHCHECK_URL HEALTHCHECK_ATTEMPTS HEALTHCHECK_INTERVAL_SECONDS"

is_boolean() { [[ "$1" == "true" || "$1" == "false" ]]; }
is_positive_integer() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ "$1" != "root" ]]; }
is_app_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$ ]] && [[ "$1" != "." && "$1" != ".." ]]; }
is_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
is_absolute_safe_path() { [[ "$1" == /* && "$1" != "/" && "$1" != *".."* && "$1" != *$'\n'* ]]; }

is_known_key() {
  local candidate="$1" key
  for key in $CONFIG_KEYS; do [[ "$candidate" == "$key" ]] && return 0; done
  return 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_config() {
  local file="$1" line key value line_number=0
  [[ -f "$file" ]] || {
    die "Configuration file not found: $file"
    return 1
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || {
      die "Invalid configuration at ${file}:${line_number}"
      return 1
    }
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
      die "Invalid key at ${file}:${line_number}"
      return 1
    }
    is_known_key "$key" || {
      die "Unknown configuration key: $key"
      return 1
    }
    [[ "$value" != *'$('* && "$value" != *'`'* && "$value" != *$'\n'* ]] ||
      {
        die "Unsafe value for $key"
        return 1
      }
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    printf -v "$key" '%s' "$value"
  done <"$file"
}

validate_config() {
  is_app_name "$APP_NAME" || { die "Invalid APP_NAME: $APP_NAME"; return 1; }
  is_username "$DEPLOY_USER" || { die "Invalid DEPLOY_USER: $DEPLOY_USER"; return 1; }
  is_absolute_safe_path "$APP_ROOT" || { die "APP_ROOT must be a safe absolute path"; return 1; }
  is_port "$SSH_PORT" || { die "SSH_PORT must be between 1 and 65535"; return 1; }
  is_positive_integer "$SWAP_SIZE_GB" || { die "SWAP_SIZE_GB must be a positive integer"; return 1; }
  is_positive_integer "$HEALTHCHECK_ATTEMPTS" || { die "HEALTHCHECK_ATTEMPTS must be positive"; return 1; }
  is_positive_integer "$HEALTHCHECK_INTERVAL_SECONDS" || { die "HEALTHCHECK_INTERVAL_SECONDS must be positive"; return 1; }
  local key
  for key in ENABLE_SYSTEM_UPGRADE ENABLE_SWAP ENABLE_UFW ENABLE_FAIL2BAN ENABLE_UNATTENDED_UPGRADES ENABLE_SSH_HARDENING; do
    is_boolean "${!key}" || { die "$key must be true or false"; return 1; }
  done
  [[ -n "$GIT_BRANCH" && "$GIT_BRANCH" != -* && "$GIT_BRANCH" != *$'\n'* ]] || { die "Invalid GIT_BRANCH"; return 1; }
  [[ -z "$GIT_REPOSITORY" || "$GIT_REPOSITORY" != -* ]] || { die "Invalid GIT_REPOSITORY"; return 1; }
}
