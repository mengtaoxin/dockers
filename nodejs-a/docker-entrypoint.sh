#!/usr/bin/env bash
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

MYSQL_SCHEMA_NAME="${MYSQL_SCHEMA_NAME:-}"
MYSQL_DATADIR="${MYSQL_DATADIR:-/var/lib/mysql}"
SOCKET="${MYSQL_UNIX_PORT:-/var/run/mysqld/mysqld.sock}"
MYSQL_PID=""

mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld "${MYSQL_DATADIR}"

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

wait_for_mysql() {
  local use_password="${1:-0}"
  local i
  for i in $(seq 1 60); do
    if [[ "${use_password}" = "1" ]]; then
      if mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent 2>/dev/null; then
        return 0
      fi
    else
      if mysqladmin --socket="${SOCKET}" --user=root ping --silent 2>/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "MySQL failed to become ready" >&2
  return 1
}

start_mysqld() {
  local extra_args=()
  if [[ $# -gt 0 ]]; then
    extra_args=("$@")
  fi
  mysqld --user=mysql --datadir="${MYSQL_DATADIR}" "${extra_args[@]}" &
  MYSQL_PID=$!
}

shutdown_mysqld() {
  if [[ -n "${MYSQL_PID}" ]] && kill -0 "${MYSQL_PID}" 2>/dev/null; then
    mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" shutdown 2>/dev/null \
      || kill "${MYSQL_PID}" 2>/dev/null \
      || true
    wait "${MYSQL_PID}" 2>/dev/null || true
  fi
}

on_signal() {
  echo "Shutting down MySQL..."
  shutdown_mysqld
  exit 0
}

trap on_signal SIGTERM SIGINT

if [[ ! -d "${MYSQL_DATADIR}/mysql" ]]; then
  echo "Initializing MySQL data directory at ${MYSQL_DATADIR}"
  mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATADIR}"

  start_mysqld --skip-networking --socket="${SOCKET}"
  wait_for_mysql 0

  root_password_sql="$(sql_quote "${MYSQL_ROOT_PASSWORD}")"
  init_sql="ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
"

  if [[ -n "${MYSQL_SCHEMA_NAME}" ]]; then
    if [[ ! "${MYSQL_SCHEMA_NAME}" =~ ^[A-Za-z0-9_]+$ ]]; then
      echo "MYSQL_SCHEMA_NAME must match [A-Za-z0-9_]+" >&2
      shutdown_mysqld
      exit 1
    fi
    init_sql+="CREATE DATABASE IF NOT EXISTS \`${MYSQL_SCHEMA_NAME}\`;"$'\n'
  fi

  init_sql+="FLUSH PRIVILEGES;"

  mysql --protocol=socket --socket="${SOCKET}" --user=root -e "${init_sql}"
  shutdown_mysqld
  MYSQL_PID=""
  echo "MySQL initialization complete"
fi

echo "Starting MySQL..."
start_mysqld
wait_for_mysql 1
echo "MySQL is ready (root password set${MYSQL_SCHEMA_NAME:+, schema ${MYSQL_SCHEMA_NAME}})"

if [[ $# -eq 0 ]] || [[ "${1}" = "mysqld" ]]; then
  # Keep container alive with MySQL running like a boot service.
  wait "${MYSQL_PID}"
  exit $?
fi

exec "$@"
