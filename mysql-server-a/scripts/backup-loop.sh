#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backup}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES:-60}"
BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT:-100}"
BACKUP_TOOL_VERSION="${BACKUP_TOOL_VERSION:-0.3.0}"
TZ="${TZ:-UTC}"
export TZ

if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  echo "MYSQL_ROOT_PASSWORD is required" >&2
  exit 1
fi

if ! [[ "${BACKUP_INTERVAL_MINUTES}" =~ ^[1-9][0-9]*$ ]]; then
  echo "BACKUP_INTERVAL_MINUTES must be a positive integer" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

mysql_args=(
  -h"${MYSQL_HOST}"
  -P"${MYSQL_PORT}"
  -u"${MYSQL_USER}"
  -p"${MYSQL_ROOT_PASSWORD}"
)

wait_for_mysql() {
  echo "waiting for MySQL at ${MYSQL_HOST}:${MYSQL_PORT}..."
  local i
  for i in $(seq 1 90); do
    if mysqladmin "${mysql_args[@]}" ping --silent >/dev/null 2>&1; then
      echo "MySQL is ready"
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for MySQL" >&2
  return 1
}

run_backup() {
  local work ts tmpzip final
  work="$(mktemp -d)"
  trap 'rm -rf "${work}"' RETURN

  echo "starting mysqldump --all-databases..."
  mysqldump "${mysql_args[@]}" \
    --all-databases \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
    >"${work}/dump.sql"

  ts="$(date +%Y%m%d-%H%M%S)"
  cat >"${work}/manifest.json" <<EOF
{
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mysql_host": "${MYSQL_HOST}",
  "mysql_major": "8.0",
  "scope": "all-databases",
  "tool_version": "${BACKUP_TOOL_VERSION}",
  "filename": "mysql-backup-${ts}.zip"
}
EOF

  tmpzip="${BACKUP_DIR}/.tmp-mysql-backup-${ts}.zip"
  final="${BACKUP_DIR}/mysql-backup-${ts}.zip"
  rm -f "${tmpzip}"
  (cd "${work}" && zip -q "${tmpzip}" dump.sql manifest.json)
  mv "${tmpzip}" "${final}"
  echo "backup written: ${final}"

  BACKUP_DIR="${BACKUP_DIR}" \
    BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT}" \
    BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES}" \
    /usr/local/bin/prune-backups.sh
}

wait_for_mysql

while true; do
  if run_backup; then
    echo "backup cycle ok; sleeping ${BACKUP_INTERVAL_MINUTES}m"
  else
    echo "backup cycle failed; sleeping ${BACKUP_INTERVAL_MINUTES}m before retry" >&2
  fi
  sleep "$((BACKUP_INTERVAL_MINUTES * 60))"
done
