#!/usr/bin/env bash
# Ensure mysqld is up, then exec the container command (agent / test / service).
set -euo pipefail

mysql-ensure-ready

if [[ $# -eq 0 ]]; then
  exec sleep infinity
fi

exec "$@"
