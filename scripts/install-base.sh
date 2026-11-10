#!/usr/bin/env bash
# Install base OS packages for agents / CI containers.
set -euo pipefail

apt-get update
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
