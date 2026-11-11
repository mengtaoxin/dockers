#!/usr/bin/env bash
# Start process-local mysqld (idempotent) and apply root password / schema on first boot.
# Env:
#   MYSQL_ROOT_PASSWORD  (required)
#   MYSQL_SCHEMA_NAME    (optional; [A-Za-z0-9_]+)
#   MYSQL_DATADIR        (default /var/lib/mysql)
#   MYSQL_BIND_ADDRESS   (default 127.0.0.1; rewritten into docker.cnf before start)
#   MYSQL_UNIX_PORT      (default /var/run/mysqld/mysqld.sock)
#   MYSQL_TEST_MODE      (0|1, default 0; 1 = speed-oriented mysqld settings for tests/CI)
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

MYSQL_SCHEMA_NAME="${MYSQL_SCHEMA_NAME:-}"
MYSQL_DATADIR="${MYSQL_DATADIR:-/var/lib/mysql}"
MYSQL_BIND_ADDRESS="${MYSQL_BIND_ADDRESS:-127.0.0.1}"
MYSQL_TEST_MODE="${MYSQL_TEST_MODE:-0}"
SOCKET="${MYSQL_UNIX_PORT:-/var/run/mysqld/mysqld.sock}"

if [[ "${MYSQL_TEST_MODE}" != "0" && "${MYSQL_TEST_MODE}" != "1" ]]; then
  echo "MYSQL_TEST_MODE must be 0 or 1" >&2
  exit 1
fi

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

write_bind_cnf() {
  {
    cat <<EOF
[mysqld]
bind-address = ${MYSQL_BIND_ADDRESS}
mysqlx-bind-address = ${MYSQL_BIND_ADDRESS}
skip-name-resolve
EOF
    if [[ "${MYSQL_TEST_MODE}" = "1" ]]; then
      # Favor speed over durability: less fsync, larger caches, fewer logs.
      # Applied on mysqld start (rewritten into docker.cnf before start).
      cat <<'EOF'
# MYSQL_TEST_MODE=1 — tests / CI only (not for production data)
innodb_flush_log_at_trx_commit = 0
innodb_doublewrite = 0
sync_binlog = 0
skip-log-bin
general_log = 0
slow_query_log = 0
performance_schema = OFF
innodb_buffer_pool_size = 256M
innodb_log_buffer_size = 64M
tmp_table_size = 64M
max_heap_table_size = 64M
EOF
    fi
  } | run_root tee /etc/mysql/mysql.conf.d/docker.cnf >/dev/null
}

wait_for_mysql() {
  local use_password="${1:-0}"
  local i
  for i in $(seq 1 60); do
    if [[ "${use_password}" = "1" ]]; then
      if run_root mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent >/dev/null 2>&1; then
        return 0
      fi
    else
      if run_root mysqladmin --socket="${SOCKET}" --user=root ping --silent >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "MySQL failed to become ready" >&2
  return 1
}

mysql_is_up() {
  run_root mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent >/dev/null 2>&1 \
    || run_root mysqladmin --socket="${SOCKET}" --user=root ping --silent >/dev/null 2>&1
}

start_mysql_service() {
  # Keep stdout clean so `docker run … image node -e '…'` only prints command output.
  if command -v service >/dev/null 2>&1; then
    run_root service mysql start >&2
  elif [[ -x /etc/init.d/mysql ]]; then
    run_root /etc/init.d/mysql start >&2
  else
    echo "Cannot start MySQL: no service(8) or /etc/init.d/mysql." >&2
    return 1
  fi
}

run_root mkdir -p /var/run/mysqld
run_root chown mysql:mysql /var/run/mysqld "${MYSQL_DATADIR}"
if [[ "${MYSQL_TEST_MODE}" = "1" ]]; then
  echo "MYSQL_TEST_MODE=1: writing speed-oriented mysqld settings" >&2
fi
write_bind_cnf

# Datadir is mysql-owned (often 700); the unprivileged image user cannot -d it.
needs_init=0
if ! run_root test -d "${MYSQL_DATADIR}/mysql"; then
  needs_init=1
fi

if [[ "${needs_init}" -eq 1 ]]; then
  echo "Initializing MySQL data directory at ${MYSQL_DATADIR}" >&2
  run_root mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATADIR}"
  start_mysql_service
  wait_for_mysql 0

  root_password_sql="$(sql_quote "${MYSQL_ROOT_PASSWORD}")"
  init_sql="ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
"

  if [[ -n "${MYSQL_SCHEMA_NAME}" ]]; then
    if [[ ! "${MYSQL_SCHEMA_NAME}" =~ ^[A-Za-z0-9_]+$ ]]; then
      echo "MYSQL_SCHEMA_NAME must match [A-Za-z0-9_]+" >&2
      exit 1
    fi
    init_sql+="CREATE DATABASE IF NOT EXISTS \`${MYSQL_SCHEMA_NAME}\`;"$'\n'
  fi

  init_sql+="FLUSH PRIVILEGES;"

  run_root mysql --protocol=socket --socket="${SOCKET}" --user=root -e "${init_sql}"
  echo "MySQL initialization complete" >&2
else
  if ! mysql_is_up; then
    echo "Starting MySQL..." >&2
    start_mysql_service
  fi
fi

wait_for_mysql 1
ready_extra=""
if [[ "${MYSQL_TEST_MODE}" = "1" ]]; then
  ready_extra+=", MYSQL_TEST_MODE=1"
fi
echo "MySQL is ready (root password set${MYSQL_SCHEMA_NAME:+, schema ${MYSQL_SCHEMA_NAME}}${ready_extra})" >&2
