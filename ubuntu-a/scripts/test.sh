#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/ubuntu-a:test"
NAME="ubuntu-a-test-$$"
NAME_TEST="ubuntu-a-test-mode-$$"
PASS="test-pass-$$"
SCHEMA="app"

cleanup() {
  docker rm -f "${NAME}" "${NAME_TEST}" >/dev/null 2>&1 || true
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
  scripts/docker-entrypoint.sh \
  scripts/mysql-ensure-ready.sh \
  scripts/install-mysql.sh \
  scripts/install-playwright-deps.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

for required in \
  scripts/install-base.sh \
  scripts/install-node.sh \
  scripts/setup-ubuntu-user.sh
do
  if [[ ! -f "${REPO_ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

docker build -f "${ROOT}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"

docker run -d --name "${NAME}" \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  -e MYSQL_BIND_ADDRESS=127.0.0.1 \
  "${IMAGE}"

mysql_ready=0
for _ in $(seq 1 90); do
  running="$(docker inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null || echo false)"
  if [[ "${running}" != "true" ]]; then
    echo "container stopped unexpectedly" >&2
    docker logs "${NAME}" >&2 || true
    exit 1
  fi

  if docker exec "${NAME}" \
    sudo mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock \
    --user=root --password="${PASS}" -N -e "SELECT 1" >/dev/null 2>&1; then
    mysql_ready=1
    break
  fi
  sleep 2
done

if [[ "${mysql_ready}" -ne 1 ]]; then
  echo "timed out waiting for MySQL" >&2
  docker logs "${NAME}" >&2 || true
  exit 1
fi

docker exec "${NAME}" node --version | grep -Eq '^v24\.'
docker exec "${NAME}" npm --version >/dev/null
docker exec "${NAME}" git --version >/dev/null
docker exec "${NAME}" jq --version >/dev/null
docker exec -u ubuntu "${NAME}" sudo -n true
docker exec "${NAME}" \
  sudo mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock \
  --user=root --password="${PASS}" -N -e "SHOW DATABASES;" 2>/dev/null \
  | grep -qx "${SCHEMA}"

# Entrypoint should start MySQL then run a one-shot command.
out="$(docker run --rm \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  "${IMAGE}" \
  node -e "process.stdout.write('node-ok')")"
[[ "${out}" == "node-ok" ]]

# MYSQL_TEST_MODE=1 should apply speed-oriented mysqld settings.
docker run -d --name "${NAME_TEST}" \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  -e MYSQL_BIND_ADDRESS=127.0.0.1 \
  -e MYSQL_TEST_MODE=1 \
  "${IMAGE}"

mysql_test_ready=0
for _ in $(seq 1 90); do
  running="$(docker inspect -f '{{.State.Running}}' "${NAME_TEST}" 2>/dev/null || echo false)"
  if [[ "${running}" != "true" ]]; then
    echo "MYSQL_TEST_MODE container stopped unexpectedly" >&2
    docker logs "${NAME_TEST}" >&2 || true
    exit 1
  fi
  if docker exec "${NAME_TEST}" \
    sudo mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock \
    --user=root --password="${PASS}" -N -e "SELECT 1" >/dev/null 2>&1; then
    mysql_test_ready=1
    break
  fi
  sleep 2
done
if [[ "${mysql_test_ready}" -ne 1 ]]; then
  echo "timed out waiting for MySQL (MYSQL_TEST_MODE=1)" >&2
  docker logs "${NAME_TEST}" >&2 || true
  exit 1
fi

mysql_var() {
  docker exec "${NAME_TEST}" \
    sudo mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock \
    --user=root --password="${PASS}" -N -e "SELECT @@${1};" \
    | tr -d '[:space:]'
}
flush="$(mysql_var innodb_flush_log_at_trx_commit)"
doublewrite="$(mysql_var innodb_doublewrite)"
perf="$(mysql_var performance_schema)"
log_bin="$(mysql_var log_bin)"
[[ "${flush}" == "0" ]] || { echo "expected innodb_flush_log_at_trx_commit=0, got ${flush}" >&2; exit 1; }
[[ "${doublewrite}" =~ ^(0|OFF)$ ]] || { echo "expected innodb_doublewrite off, got ${doublewrite}" >&2; exit 1; }
[[ "${perf}" =~ ^(0|OFF)$ ]] || { echo "expected performance_schema off, got ${perf}" >&2; exit 1; }
[[ "${log_bin}" =~ ^(0|OFF)$ ]] || { echo "expected log_bin off, got ${log_bin}" >&2; exit 1; }

# Idempotent ensure from an already-running container.
docker exec -e MYSQL_ROOT_PASSWORD="${PASS}" -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  "${NAME}" mysql-ensure-ready >/dev/null

status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${NAME}")"
echo "health=${status}"

echo "ubuntu-a OK (${version})"
