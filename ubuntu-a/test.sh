#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="dockers-test/ubuntu-a:test"
NAME="ubuntu-a-test-$$"
PASS="test-pass-$$"
SCHEMA="app"

cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
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
  docker-entrypoint.sh \
  mysql-ensure-ready.sh \
  scripts/install-base.sh \
  scripts/install-node.sh \
  scripts/install-playwright-deps.sh \
  scripts/setup-ubuntu-user.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

docker build -t "${IMAGE}" "${ROOT}"

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

# Idempotent ensure from an already-running container.
docker exec -e MYSQL_ROOT_PASSWORD="${PASS}" -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  "${NAME}" mysql-ensure-ready >/dev/null

status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${NAME}")"
echo "health=${status}"

echo "ubuntu-a OK (${version})"
