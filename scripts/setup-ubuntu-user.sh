#!/usr/bin/env bash
# Ensure the ubuntu user exists with passwordless sudo.
# Optional EXTRA_GROUPS (comma-separated) are appended after sudo, e.g. mysql.
set -euo pipefail

id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
usermod -aG "sudo${EXTRA_GROUPS:+,${EXTRA_GROUPS}}" ubuntu
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu
