#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/mysql-server-a:test"
NAME="mysql-server-a-test-$$"
BACKUP_HOST_DIR="$(mktemp -d)"
MYSQL_DATA_DIR="$(mktemp -d)"
MYSQL_LOGS_DIR="$(mktemp -d)"
HOST_PMA_PORT=""

cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  host_uid="$(id -u)"
  host_gid="$(id -g)"
  for d in "${MYSQL_DATA_DIR}" "${MYSQL_LOGS_DIR}" "${BACKUP_HOST_DIR}"; do
    if [[ -d "${d}" ]]; then
      docker run --rm -v "${d}:/v" --entrypoint bash "${IMAGE}" -lc \
        "find /v -mindepth 1 -delete; chown ${host_uid}:${host_gid} /v" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "${BACKUP_HOST_DIR}" "${MYSQL_DATA_DIR}" "${MYSQL_LOGS_DIR}" || true
}
trap cleanup EXIT

version="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid VERSION: ${version}" >&2
  exit 1
fi

for required in \
  Dockerfile \
  compose.yaml \
  README.md \
  mysql/conf.d/zz-logging.cnf \
  apache/phpmyadmin.conf \
  scripts/backup-loop.sh \
  scripts/prune-backups.sh \
  scripts/docker-entrypoint.sh \
  scripts/mysql-ensure-ready.sh \
  scripts/install-mysql.sh \
  scripts/install-phpmyadmin.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

if ! grep -q 'MYSQL_NATIVE_PASSWORD' "${ROOT}/compose.yaml"; then
  echo "compose.yaml must expose MYSQL_NATIVE_PASSWORD" >&2
  exit 1
fi
if ! grep -q 'MYSQL_NATIVE_PASSWORD' "${ROOT}/README.md"; then
  echo "README.md must document MYSQL_NATIVE_PASSWORD" >&2
  exit 1
fi
if ! grep -q 'utf8mb4' "${ROOT}/README.md"; then
  echo "README.md must mention utf8mb4" >&2
  exit 1
fi
if grep -qE '^\s+phpmyadmin:|^\s+backup-tool:' "${ROOT}/compose.yaml"; then
  echo "compose.yaml must be a single-service all-in-one stack" >&2
  exit 1
fi

docker build -f "${ROOT}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"

docker run --rm --entrypoint bash "${IMAGE}" -lc \
  'command -v mysqld && command -v mysqldump && command -v zip && command -v mysqladmin && command -v apache2ctl && test -d /var/www/phpmyadmin && test -x /usr/local/bin/backup-loop.sh && test -x /usr/local/bin/prune-backups.sh && test -x /usr/local/bin/mysql-ensure-ready'

# Seed backups spanning recent / mid / older windows and verify prune.
now_day="$(date -u +%Y%m%d)"
day0="${now_day}"
day1="$(date -u -d "${now_day} -1 day" +%Y%m%d 2>/dev/null || date -u -j -v-1d -f "%Y%m%d" "${now_day}" +%Y%m%d)"
day5="$(date -u -d "${now_day} -5 day" +%Y%m%d 2>/dev/null || date -u -j -v-5d -f "%Y%m%d" "${now_day}" +%Y%m%d)"
day10="$(date -u -d "${now_day} -10 day" +%Y%m%d 2>/dev/null || date -u -j -v-10d -f "%Y%m%d" "${now_day}" +%Y%m%d)"

for stamp in \
  "${day0}-120000" "${day0}-130000" "${day0}-140000" \
  "${day1}-120000" "${day1}-130000" \
  "${day5}-120000" "${day5}-130000" "${day5}-140000" \
  "${day10}-120000" "${day10}-130000"
do
  : >"${BACKUP_HOST_DIR}/mysql-backup-${stamp}.zip"
done

docker run --rm \
  --entrypoint bash \
  -e BACKUP_DIR=/backup \
  -e BACKUP_KEEP_COUNT=5 \
  -e BACKUP_INTERVAL_MINUTES=60 \
  -e TZ=UTC \
  -v "${BACKUP_HOST_DIR}:/backup" \
  "${IMAGE}" \
  -lc '/usr/local/bin/prune-backups.sh'

remaining="$(find "${BACKUP_HOST_DIR}" -name 'mysql-backup-*.zip' | wc -l | tr -d ' ')"
if [[ "${remaining}" -gt 5 ]]; then
  echo "expected at most 5 backups after prune, got ${remaining}" >&2
  ls -la "${BACKUP_HOST_DIR}" >&2
  exit 1
fi
if [[ "${remaining}" -lt 1 ]]; then
  echo "expected some backups to remain after prune" >&2
  exit 1
fi

older_count="$(find "${BACKUP_HOST_DIR}" -name "mysql-backup-${day10}-*.zip" | wc -l | tr -d ' ')"
if [[ "${older_count}" -gt 1 ]]; then
  echo "expected at most 1 backup for older day ${day10}, got ${older_count}" >&2
  ls -la "${BACKUP_HOST_DIR}" >&2
  exit 1
fi

# Fresh backup dir for the live container run.
rm -f "${BACKUP_HOST_DIR}"/mysql-backup-*.zip

# Pick a free host port for phpMyAdmin.
HOST_PMA_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"

docker run -d --name "${NAME}" \
  -e MYSQL_ROOT_PASSWORD=testpass \
  -e TZ=Asia/Shanghai \
  -e MYSQL_NATIVE_PASSWORD=1 \
  -e BACKUP_INTERVAL_MINUTES=60 \
  -e BACKUP_KEEP_COUNT=100 \
  -p "127.0.0.1:${HOST_PMA_PORT}:80" \
  -v "${MYSQL_DATA_DIR}:/var/lib/mysql" \
  -v "${MYSQL_LOGS_DIR}:/logs" \
  -v "${BACKUP_HOST_DIR}:/backup" \
  "${IMAGE}"

ready=0
for _ in $(seq 1 90); do
  if docker exec "${NAME}" mysqladmin --socket=/var/run/mysqld/mysqld.sock -uroot -ptestpass ping --silent >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "${ready}" -ne 1 ]]; then
  echo "mysqld did not become ready" >&2
  docker logs "${NAME}" >&2 || true
  exit 1
fi

vars="$(docker exec "${NAME}" mysql --socket=/var/run/mysqld/mysqld.sock -N -uroot -ptestpass -e \
  "SELECT @@global.time_zone, @@character_set_server, @@collation_server, @@global.default_authentication_plugin;")"
read -r got_tz got_charset got_collation got_plugin <<<"${vars}"
if [[ "${got_tz}" != "+08:00" ]]; then
  echo "expected @@global.time_zone=+08:00, got ${got_tz}" >&2
  exit 1
fi
if [[ "${got_charset}" != "utf8mb4" ]]; then
  echo "expected @@character_set_server=utf8mb4, got ${got_charset}" >&2
  exit 1
fi
if [[ "${got_collation}" != "utf8mb4_unicode_ci" ]]; then
  echo "expected @@collation_server=utf8mb4_unicode_ci, got ${got_collation}" >&2
  exit 1
fi
if [[ "${got_plugin}" != "mysql_native_password" ]]; then
  echo "expected default_authentication_plugin=mysql_native_password, got ${got_plugin}" >&2
  exit 1
fi

bind_addr="$(docker exec "${NAME}" mysql --socket=/var/run/mysqld/mysqld.sock -N -uroot -ptestpass -e \
  "SHOW VARIABLES LIKE 'bind_address';" | awk '{print $2}')"
if [[ "${bind_addr}" != "0.0.0.0" ]]; then
  echo "expected bind_address=0.0.0.0, got ${bind_addr}" >&2
  exit 1
fi

pma_ok=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOST_PMA_PORT}/" || true)"
  if [[ "${code}" == "200" || "${code}" == "302" || "${code}" == "401" ]]; then
    pma_ok=1
    break
  fi
  sleep 2
done
if [[ "${pma_ok}" -ne 1 ]]; then
  echo "phpMyAdmin HTTP did not become ready (last code=${code:-none})" >&2
  docker logs "${NAME}" >&2 || true
  exit 1
fi

if ! docker exec "${NAME}" bash -lc 'ps aux | grep -v grep | grep -q backup-loop.sh'; then
  echo "backup-loop is not running" >&2
  docker logs "${NAME}" >&2 || true
  exit 1
fi

echo "mysql-server-a OK (${version})"
