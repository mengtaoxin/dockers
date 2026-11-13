#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/mysql-restore-tool-a:test"
BACKUP_HOST_DIR="$(mktemp -d)"

cleanup() {
  # restore writes mysql-owned files into the bind mount; host rm can fail on GHA.
  if [[ -d "${BACKUP_HOST_DIR}" ]]; then
    docker run --rm -v "${BACKUP_HOST_DIR}:/v" --entrypoint bash mysql:8.0 -lc \
      'rm -rf /v/* /v/.[!.]* /v/..?*' >/dev/null 2>&1 || true
  fi
  rm -rf "${BACKUP_HOST_DIR}"
}
trap cleanup EXIT

version="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid VERSION: ${version}" >&2
  exit 1
fi

for required in Dockerfile compose.yaml README.md scripts/restore.sh; do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

docker build -f "${ROOT}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"

docker run --rm --entrypoint bash "${IMAGE}" -lc \
  'command -v mysqld && command -v mysql && command -v unzip && test -x /usr/local/bin/restore.sh'

# Help / missing-file paths.
docker run --rm "${IMAGE}" --help | grep -q -- '--file'
if docker run --rm -v "${BACKUP_HOST_DIR}:/backup" "${IMAGE}" --file mysql-backup-20990101-000000.zip; then
  echo "expected missing-file restore to fail" >&2
  exit 1
fi

# Minimal dump → datadir smoke (needs mysqld inside the image).
WORK="$(mktemp -d)"
cat >"${WORK}/dump.sql" <<'EOF'
CREATE DATABASE IF NOT EXISTS restore_smoke;
USE restore_smoke;
CREATE TABLE t (id INT PRIMARY KEY, name VARCHAR(32));
INSERT INTO t VALUES (1, 'ok');
EOF
cat >"${WORK}/manifest.json" <<'EOF'
{"mysql_major":"8.0","scope":"all-databases"}
EOF
(cd "${WORK}" && zip -q "${BACKUP_HOST_DIR}/mysql-backup-20990101-120000.zip" dump.sql manifest.json)
rm -rf "${WORK}"

docker run --rm \
  -v "${BACKUP_HOST_DIR}:/backup" \
  "${IMAGE}" \
  --file mysql-backup-20990101-120000.zip

OUT="${BACKUP_HOST_DIR}/mysql-backup-20990101-120000"
if [[ ! -d "${OUT}/mysql" ]]; then
  echo "expected system mysql/ directory in restored datadir" >&2
  ls -la "${BACKUP_HOST_DIR}" >&2
  ls -la "${OUT}" >&2 || true
  exit 1
fi

echo "mysql-restore-tool-a OK (${version})"
