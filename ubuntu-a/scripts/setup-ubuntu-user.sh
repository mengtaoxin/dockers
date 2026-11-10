#!/usr/bin/env bash
# Ensure the ubuntu user exists with passwordless sudo and mysql group membership.
set -euo pipefail

id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
usermod -aG sudo,mysql ubuntu
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu
