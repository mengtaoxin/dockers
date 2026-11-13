#!/usr/bin/env bash
# Install MySQL server for the all-in-one mysql-server-a image.
set -euo pipefail

: "${MYSQL_BIND_ADDRESS:=0.0.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apt-update.sh"
apt-get install -y --no-install-recommends mysql-server

mkdir -p /var/run/mysqld /logs
chown mysql:mysql /var/run/mysqld
rm -rf /var/lib/mysql/*
chown mysql:mysql /var/lib/mysql
usermod -d /var/lib/mysql mysql

printf '%s\n' \
  '[mysqld]' \
  "bind-address = ${MYSQL_BIND_ADDRESS}" \
  "mysqlx-bind-address = ${MYSQL_BIND_ADDRESS}" \
  'skip-name-resolve' \
  > /etc/mysql/mysql.conf.d/docker.cnf

mysqld --version
