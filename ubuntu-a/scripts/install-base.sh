#!/usr/bin/env bash
# Install base OS packages and prepare process-local MySQL layout.
set -euo pipefail

: "${MYSQL_BIND_ADDRESS:=127.0.0.1}"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  git \
  jq \
  lsof \
  netcat-openbsd \
  sudo \
  mysql-server \
  xz-utils

mkdir -p /var/run/mysqld
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
