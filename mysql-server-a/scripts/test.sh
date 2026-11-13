#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/mysql-server-a:test"
NAME="mysql-server-a-prune-test-$$"
MYSQL_NAME="mysql-server-a-mysqld-test-$$"
BACKUP_HOST_DIR="$(mktemp -d)"
MYSQL_DATA_DIR="$(mktemp -d)"
MYSQL_LOGS_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  docker rm -f "${MYSQL_NAME}" >/dev/null 2>&1 || true
  # mysqld may leave mysql-owned files in bind mounts; host rm can fail on GHA.
  for d in "${MYSQL_DATA_DIR}" "${MYSQL_LOGS_DIR}"; do
    if [[ -d "${d}" ]]; then
      docker run --rm -v "${d}:/v" --entrypoint bash mysql:8.0 -lc 'rm -rf /v/* /v/.[!.]* /v/..?*' >/dev/null 2>&1 || true
    fi
  done
  rm -rf "${BACKUP_HOST_DIR}" "${MYSQL_DATA_DIR}" "${MYSQL_LOGS_DIR}"
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
  mysql/conf.d/logging.cnf \
  scripts/backup-loop.sh \
  scripts/prune-backups.sh \
  scripts/mysqld-entrypoint.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

if ! grep -q 'mysqld-entrypoint.sh' "${ROOT}/compose.yaml"; then
  echo "compose.yaml must wire mysqld-entrypoint.sh" >&2
  exit 1
fi
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

docker build -f "${ROOT}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"

docker run --rm --entrypoint bash "${IMAGE}" -lc \
  'command -v mysqldump && command -v zip && command -v mysqladmin && test -x /usr/local/bin/backup-loop.sh && test -x /usr/local/bin/prune-backups.sh'

# Seed backups spanning recent / mid / older windows and verify prune.
# Use fixed timestamps relative to "now" inside the container TZ=UTC.
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

# Older day should keep only the newest file for that day when older_per_day=1.
older_count="$(find "${BACKUP_HOST_DIR}" -name "mysql-backup-${day10}-*.zip" | wc -l | tr -d ' ')"
if [[ "${older_count}" -gt 1 ]]; then
  echo "expected at most 1 backup for older day ${day10}, got ${older_count}" >&2
  ls -la "${BACKUP_HOST_DIR}" >&2
  exit 1
fi

# --- mysqld entrypoint acceptance (native password + TZ + utf8mb4) ---
docker run -d --name "${MYSQL_NAME}" \
  -e MYSQL_ROOT_PASSWORD=testpass \
  -e TZ=Asia/Shanghai \
  -e MYSQL_NATIVE_PASSWORD=1 \
  -v "${MYSQL_DATA_DIR}:/var/lib/mysql" \
  -v "${MYSQL_LOGS_DIR}:/logs" \
  -v "${ROOT}/mysql/conf.d:/etc/mysql/conf.d:ro" \
  -v "${ROOT}/scripts/mysqld-entrypoint.sh:/mysqld-entrypoint.sh:ro" \
  --entrypoint /mysqld-entrypoint.sh \
  mysql:8.0

ready=0
for _ in $(seq 1 60); do
  if docker exec "${MYSQL_NAME}" mysqladmin ping -h127.0.0.1 -uroot -ptestpass --silent >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "${ready}" -ne 1 ]]; then
  echo "mysqld did not become ready" >&2
  docker logs "${MYSQL_NAME}" >&2 || true
  exit 1
fi

vars="$(docker exec "${MYSQL_NAME}" mysql -N -uroot -ptestpass -e \
  "SELECT @@global.time_zone, @@character_set_server, @@collation_server, @@global.default_authentication_plugin;")"
# Expect: +08:00 utf8mb4 utf8mb4_unicode_ci mysql_native_password
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

echo "mysql-server-a OK (${version})"
