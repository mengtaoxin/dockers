#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/mysql-server-a:test"
NAME="mysql-server-a-prune-test-$$"
BACKUP_HOST_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  rm -rf "${BACKUP_HOST_DIR}"
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
  scripts/prune-backups.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

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

echo "mysql-server-a OK (${version})"
