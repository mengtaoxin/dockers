#!/usr/bin/env bash
# Start process-local mysqld (idempotent) and apply root password on first boot.
# Env:
#   MYSQL_ROOT_PASSWORD     (required)
#   MYSQL_DATADIR           (default /var/lib/mysql)
#   MYSQL_BIND_ADDRESS      (default 0.0.0.0)
#   MYSQL_UNIX_PORT         (default /var/run/mysqld/mysqld.sock)
#   MYSQL_NATIVE_PASSWORD   (0|1; default 0)
#   TZ                      (IANA name; used for mysqld default-time-zone)
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

MYSQL_DATADIR="${MYSQL_DATADIR:-/var/lib/mysql}"
MYSQL_BIND_ADDRESS="${MYSQL_BIND_ADDRESS:-0.0.0.0}"
SOCKET="${MYSQL_UNIX_PORT:-/var/run/mysqld/mysqld.sock}"
TZ="${TZ:-UTC}"
export TZ

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

derive_mysql_tz() {
  local raw_offset
  raw_offset="$(TZ="${TZ}" date +%z)" # e.g. +0800 / -0500
  if [[ ! "${raw_offset}" =~ ^[+-][0-9]{4}$ ]]; then
    echo "mysql-ensure-ready: cannot derive MySQL time zone offset from TZ=${TZ} (got: ${raw_offset})" >&2
    exit 1
  fi
  printf '%s' "${raw_offset:0:3}:${raw_offset:3:2}"
}

auth_plugin() {
  local native="${MYSQL_NATIVE_PASSWORD:-0}"
  case "${native}" in
    1 | true | TRUE | yes | YES | on | ON)
      printf '%s' "mysql_native_password"
      ;;
    0 | false | FALSE | no | NO | off | OFF | "")
      printf '%s' "caching_sha2_password"
      ;;
    *)
      echo "mysql-ensure-ready: invalid MYSQL_NATIVE_PASSWORD=${native} (use 0/1 or true/false)" >&2
      exit 1
      ;;
  esac
}

write_runtime_cnf() {
  local mysql_tz plugin
  mysql_tz="$(derive_mysql_tz)"
  plugin="$(auth_plugin)"

  cat > /etc/mysql/mysql.conf.d/docker.cnf <<EOF
[mysqld]
bind-address = ${MYSQL_BIND_ADDRESS}
mysqlx-bind-address = ${MYSQL_BIND_ADDRESS}
skip-name-resolve
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default-time-zone = ${mysql_tz}
default_authentication_plugin = ${plugin}
EOF
}

wait_for_mysql() {
  local use_password="${1:-0}"
  local i
  for i in $(seq 1 90); do
    if [[ "${use_password}" = "1" ]]; then
      if mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent >/dev/null 2>&1; then
        return 0
      fi
    else
      if mysqladmin --socket="${SOCKET}" --user=root ping --silent >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "MySQL failed to become ready" >&2
  return 1
}

mysql_is_up() {
  mysqladmin --socket="${SOCKET}" --user=root --password="${MYSQL_ROOT_PASSWORD}" ping --silent >/dev/null 2>&1 \
    || mysqladmin --socket="${SOCKET}" --user=root ping --silent >/dev/null 2>&1
}

start_mysql_service() {
  if command -v service >/dev/null 2>&1; then
    service mysql start >&2
  elif [[ -x /etc/init.d/mysql ]]; then
    /etc/init.d/mysql start >&2
  else
    echo "Cannot start MySQL: no service(8) or /etc/init.d/mysql." >&2
    return 1
  fi
}

mkdir -p /var/run/mysqld "${MYSQL_DATADIR}"
chown mysql:mysql /var/run/mysqld "${MYSQL_DATADIR}"
write_runtime_cnf

needs_init=0
if ! test -d "${MYSQL_DATADIR}/mysql"; then
  needs_init=1
fi

plugin="$(auth_plugin)"

if [[ "${needs_init}" -eq 1 ]]; then
  echo "Initializing MySQL data directory at ${MYSQL_DATADIR}" >&2
  mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATADIR}"
  start_mysql_service
  wait_for_mysql 0

  root_password_sql="$(sql_quote "${MYSQL_ROOT_PASSWORD}")"
  init_sql="ALTER USER 'root'@'localhost' IDENTIFIED WITH ${plugin} BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH ${plugin} BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH ${plugin} BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;"

  mysql --protocol=socket --socket="${SOCKET}" --user=root -e "${init_sql}"
  echo "MySQL initialization complete" >&2
else
  if ! mysql_is_up; then
    echo "Starting MySQL..." >&2
    start_mysql_service
  fi
fi

wait_for_mysql 1
echo "MySQL is ready (root password set, plugin=${plugin}, tz=$(derive_mysql_tz))" >&2
