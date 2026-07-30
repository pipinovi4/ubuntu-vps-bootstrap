#!/usr/bin/env bash

install_docker() {
  local keyring=/etc/apt/keyrings/docker.asc list=/etc/apt/sources.list.d/docker.list arch codename
  arch="$(dpkg --print-architecture)"
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="$VERSION_CODENAME"
  run install -m 0755 -d /etc/apt/keyrings
  if [[ ! -s "$keyring" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      run curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$keyring"
    else
      local temp_key
      temp_key="$(mktemp)"
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$temp_key"
      gpg --show-keys "$temp_key" >/dev/null
      install -m 0644 "$temp_key" "$keyring"
      rm -f -- "$temp_key"
    fi
  fi
  local repository="deb [arch=${arch} signed-by=${keyring}] https://download.docker.com/linux/ubuntu ${codename} stable"
  if [[ ! -f "$list" ]] || [[ "$(cat "$list")" != "$repository" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log DRY-RUN "write Docker apt repository to $list"
    else
      backup_file "$list"
      printf '%s\n' "$repository" >"${list}.tmp"
      chmod 0644 "${list}.tmp"
      mv -f -- "${list}.tmp" "$list"
    fi
  fi
  run apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  enable_service docker
  if [[ "$DRY_RUN" != "true" ]]; then
    docker --version
    docker compose version
  fi
  record_completed "Docker Engine and Compose plugin installed"
}
