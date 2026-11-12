#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/github-actions-runner-a:test"
NAME="github-actions-runner-a-test-$$"
NAME_TEST="github-actions-runner-a-test-mode-$$"
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
  scripts/install-deps.sh \
  scripts/smb-mount.sh \
  scripts/filecopy.sh \
  scripts/filecopy-smb.sh
do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

entrypoint="${ROOT}/scripts/docker-entrypoint.sh"
grep -q -- '--ephemeral' "${entrypoint}" || {
  echo "entrypoint missing --ephemeral" >&2
  exit 1
}
grep -q -- '--disableupdate' "${entrypoint}" || {
  echo "entrypoint missing --disableupdate" >&2
  exit 1
}
grep -q 'Configuring ephemeral runner' "${entrypoint}" || {
  echo "entrypoint missing always-register ephemeral configure path" >&2
  exit 1
}
# Exactly one .runner existence gate is OK (remove_runner); a second would reintroduce skip-on-reuse.
runner_gate_count="$(grep -cE 'if \[\[ ! -f "\$\{RUNNER_HOME\}/\.runner" \]\]' "${entrypoint}" || true)"
if [[ "${runner_gate_count}" -ne 1 ]]; then
  echo "expected exactly one .runner existence check (remove_runner), got ${runner_gate_count}" >&2
  exit 1
fi

docker build -f "${ROOT}/Dockerfile" -t "${IMAGE}" "${REPO_ROOT}"

docker run -d --name "${NAME}" \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  -e MYSQL_BIND_ADDRESS=127.0.0.1 \
  "${IMAGE}" \
  sleep infinity

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

docker exec "${NAME}" sshpass -V >/dev/null
docker exec "${NAME}" smbclient --version >/dev/null
docker exec "${NAME}" sh -c 'command -v mount.cifs' >/dev/null
docker exec "${NAME}" gh --version >/dev/null

# smb-mount must be a no-op when SMB_HOST is unset.
docker exec "${NAME}" smb-mount 2>&1 | grep -q 'skipping SMB mount'
docker exec "${NAME}" test -d /mnt/smb

# smb-mount must fail loudly when SMB_HOST is set but credentials/share are missing.
if docker exec -e SMB_HOST=127.0.0.1 "${NAME}" smb-mount >/dev/null 2>&1; then
  echo "smb-mount should fail with incomplete SMB config" >&2
  exit 1
fi

# filecopy: help / argument validation, offline (no SMB server required).
docker exec "${NAME}" filecopy --help 2>&1 | grep -q 'Usage: filecopy'
docker exec "${NAME}" command -v filecopy-smb >/dev/null
if docker exec "${NAME}" filecopy >/dev/null 2>&1; then
  echo "filecopy should fail without arguments" >&2
  exit 1
fi
if docker exec "${NAME}" filecopy /no/such/file y.zip >/dev/null 2>&1; then
  echo "filecopy should fail when the local file is missing" >&2
  exit 1
fi
if docker exec -e FILE_COPY_TYPE=ftp "${NAME}" filecopy /etc/hostname y.zip >/dev/null 2>&1; then
  echo "filecopy should fail for an unsupported FILE_COPY_TYPE" >&2
  exit 1
fi
if docker exec "${NAME}" filecopy /etc/hostname y.zip >/dev/null 2>&1; then
  echo "filecopy-smb should fail when SMB_* config is missing" >&2
  exit 1
fi

docker exec "${NAME}" mysqld --version >/dev/null
docker exec -u runner "${NAME}" sudo -n true
docker exec "${NAME}" \
  sudo mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock \
  --user=root --password="${PASS}" -N -e "SHOW DATABASES;" 2>/dev/null \
  | grep -qx "${SCHEMA}"

# Entrypoint should start MySQL then run a one-shot command (no GitHub registration).
out="$(docker run --rm \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  "${IMAGE}" \
  bash -lc 'printf tools-ok')"
[[ "${out}" == *tools-ok* ]]

# MYSQL_TEST_MODE=1 should apply speed-oriented mysqld settings.
docker run -d --name "${NAME_TEST}" \
  -e MYSQL_ROOT_PASSWORD="${PASS}" \
  -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  -e MYSQL_BIND_ADDRESS=127.0.0.1 \
  -e MYSQL_TEST_MODE=1 \
  "${IMAGE}" \
  sleep infinity

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

docker exec -e MYSQL_ROOT_PASSWORD="${PASS}" -e MYSQL_SCHEMA_NAME="${SCHEMA}" \
  "${NAME}" mysql-ensure-ready >/dev/null

status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${NAME}")"
echo "health=${status}"

echo "github-actions-runner-a OK (${version})"
