#!/usr/bin/env bash
# Install runner extras: sshpass, smbclient, GitHub CLI (gh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apt-update.sh"
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  smbclient \
  sshpass

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

arch="$(dpkg --print-architecture)"
echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

bash "${SCRIPT_DIR}/apt-update.sh"
apt-get install -y --no-install-recommends gh

sshpass -V
smbclient --version
gh --version
