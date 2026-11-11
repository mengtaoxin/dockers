#!/usr/bin/env bash
# Install base OS packages for agents / CI containers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apt-update.sh"
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  git \
  jq \
  lsof \
  netcat-openbsd \
  sudo \
  xz-utils
