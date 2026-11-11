#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="dockers-test/hello-world:test"

version="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid VERSION: ${version}" >&2
  exit 1
fi

for required in Dockerfile compose.yaml; do
  if [[ ! -f "${ROOT}/${required}" ]]; then
    echo "missing ${required}" >&2
    exit 1
  fi
done

docker build --network=host -t "${IMAGE}" "${ROOT}"

out="$(docker run --rm "${IMAGE}")"
expected="Hello from dockers/hello-world"
if [[ "${out}" != *"${expected}"* ]]; then
  echo "unexpected output: ${out}" >&2
  exit 1
fi

echo "hello-world OK (${version})"
