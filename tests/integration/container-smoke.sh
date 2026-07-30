#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
image="${UBUNTU_TEST_IMAGE:-ubuntu:24.04}"
docker run --rm -v "$ROOT:/work:ro" "$image" bash -c '
  set -Eeuo pipefail
  /work/bootstrap.sh --help >/dev/null
  /work/deploy.sh --help >/dev/null
  /work/uninstall.sh --help >/dev/null
  source /work/lib/common.sh
  source /work/lib/config.sh
  validate_config
'
printf 'Container smoke tests passed using %s\n' "$image"
