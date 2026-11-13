#!/usr/bin/env bash
# Wrap official mysql:8.0 entrypoint: fixed utf8mb4, TZ→default-time-zone,
# optional mysql_native_password. Still uses /usr/local/bin/docker-entrypoint.sh.
set -euo pipefail

tz="${TZ:-UTC}"
raw_offset="$(TZ="${tz}" date +%z)" # e.g. +0800 / -0500
if [[ ! "${raw_offset}" =~ ^[+-][0-9]{4}$ ]]; then
  echo "mysqld-entrypoint: cannot derive MySQL time zone offset from TZ=${tz} (got: ${raw_offset})" >&2
  exit 1
fi
mysql_tz="${raw_offset:0:3}:${raw_offset:3:2}" # +08:00

extra=(
  --character-set-server=utf8mb4
  --collation-server=utf8mb4_unicode_ci
  --default-time-zone="${mysql_tz}"
)

native="${MYSQL_NATIVE_PASSWORD:-0}"
case "${native}" in
  1 | true | TRUE | yes | YES | on | ON)
    extra+=(--default-authentication-plugin=mysql_native_password)
    ;;
  0 | false | FALSE | no | NO | off | OFF | "")
    ;;
  *)
    echo "mysqld-entrypoint: invalid MYSQL_NATIVE_PASSWORD=${native} (use 0/1 or true/false)" >&2
    exit 1
    ;;
esac

# Official image: args after mysqld are passed to the server.
if [[ $# -eq 0 || "${1}" == "mysqld" ]]; then
  if [[ $# -eq 0 ]]; then
    set -- mysqld
  fi
  set -- "$@" "${extra[@]}"
else
  # Non-mysqld command (e.g. bash): do not inject server flags.
  :
fi

# logging.cnf → /logs/error.log. Bind mounts are often host-UID-owned; mysqld runs as mysql.
if [[ -d /logs ]]; then
  chown mysql:mysql /logs || chmod 0777 /logs
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
