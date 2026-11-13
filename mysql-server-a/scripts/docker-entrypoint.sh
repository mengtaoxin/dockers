#!/usr/bin/env bash
# Start MySQL, phpMyAdmin (Apache), and the backup loop in one container.
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

TZ="${TZ:-UTC}"
export TZ
BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES:-60}"
BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT:-100}"
BACKUP_TOOL_VERSION="${BACKUP_TOOL_VERSION:-}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

APACHE_PID=""
BACKUP_PID=""

shutdown() {
  local ec="${1:-0}"
  echo "shutting down (exit ${ec})..." >&2
  if [[ -n "${BACKUP_PID}" ]] && kill -0 "${BACKUP_PID}" 2>/dev/null; then
    kill "${BACKUP_PID}" 2>/dev/null || true
    wait "${BACKUP_PID}" 2>/dev/null || true
  fi
  if command -v service >/dev/null 2>&1; then
    service apache2 stop >/dev/null 2>&1 || true
    service mysql stop >/dev/null 2>&1 || true
  fi
  if [[ -n "${APACHE_PID}" ]] && kill -0 "${APACHE_PID}" 2>/dev/null; then
    kill "${APACHE_PID}" 2>/dev/null || true
    wait "${APACHE_PID}" 2>/dev/null || true
  fi
  exit "${ec}"
}

trap 'shutdown 0' SIGTERM SIGINT

# zz-logging.cnf → /logs/error.log. Bind mounts are often host-UID-owned.
# chmod the dir (do not chown it): chown breaks host cleanup under /tmp sticky bit on GHA.
mkdir -p /logs "${BACKUP_DIR}"
if [[ -d /logs ]]; then
  chmod 0777 /logs
  touch /logs/error.log
  chown mysql:mysql /logs/error.log
fi

mysql-ensure-ready

# phpMyAdmin config: talk to the local mysqld.
pma_config="/var/www/phpmyadmin/config.inc.php"
if [[ ! -f "${pma_config}" ]]; then
  # Avoid `tr | head` under pipefail (SIGPIPE can abort the entrypoint).
  blowfish="$(dd if=/dev/urandom bs=32 count=1 status=none | base64 | tr -d '\n+/=' | cut -c1-32)"
  cat >"${pma_config}" <<EOF
<?php
\$cfg['blowfish_secret'] = '${blowfish}';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
\$cfg['Servers'][\$i]['port'] = '3306';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
EOF
  chown www-data:www-data "${pma_config}"
fi

# Start Apache in the foreground under a background job we can wait on.
apache2ctl -D FOREGROUND &
APACHE_PID=$!
echo "Apache started (pid ${APACHE_PID})" >&2

BACKUP_TOOL_VERSION="${BACKUP_TOOL_VERSION:-0.3.0}"

MYSQL_HOST="${MYSQL_HOST}" \
MYSQL_PORT="${MYSQL_PORT}" \
MYSQL_USER=root \
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
BACKUP_DIR="${BACKUP_DIR}" \
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES}" \
BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT}" \
BACKUP_TOOL_VERSION="${BACKUP_TOOL_VERSION}" \
TZ="${TZ}" \
  /usr/local/bin/backup-loop.sh &
BACKUP_PID=$!
echo "backup-loop started (pid ${BACKUP_PID})" >&2

# Keep the container alive while children run; exit if either dies.
while true; do
  if ! kill -0 "${APACHE_PID}" 2>/dev/null; then
    echo "Apache exited unexpectedly" >&2
    shutdown 1
  fi
  if ! kill -0 "${BACKUP_PID}" 2>/dev/null; then
    echo "backup-loop exited unexpectedly" >&2
    shutdown 1
  fi
  # mysqld is managed by the service supervisor; verify it stays up.
  if ! mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent >/dev/null 2>&1; then
    echo "mysqld is no longer reachable" >&2
    shutdown 1
  fi
  sleep 5
done
