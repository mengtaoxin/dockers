#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/.." && pwd)"
IMAGE="dockers-test/ubuntu-b:test"
NAME="ubuntu-b-test-$$"
PLAYWRIGHT_VERSION=1.64.1

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
  scripts/install-playwright.sh
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

docker run -d --name "${NAME}" --init --ipc=host "${IMAGE}"

docker exec "${NAME}" node --version | grep -Eq '^v24\.'
docker exec "${NAME}" npm --version >/dev/null
docker exec "${NAME}" git --version >/dev/null
docker exec "${NAME}" jq --version >/dev/null
docker exec -u ubuntu "${NAME}" sudo -n true

browsers_path="$(docker exec "${NAME}" printenv PLAYWRIGHT_BROWSERS_PATH)"
[[ "${browsers_path}" == "/ms-playwright" ]]
docker exec "${NAME}" bash -c 'ls /ms-playwright | grep -Eq "chromium-"'
docker exec "${NAME}" bash -c 'ls /ms-playwright | grep -Eq "firefox-"'
docker exec "${NAME}" bash -c 'ls /ms-playwright | grep -Eq "webkit-"'

# Launch Chromium via a matching Playwright package (browsers already baked in).
out="$(docker run --rm --init --ipc=host -w /tmp "${IMAGE}" bash -lc "
  set -euo pipefail
  npm init -y >/dev/null
  npm install --no-save --no-fund --no-audit playwright@${PLAYWRIGHT_VERSION} >/dev/null
  node <<'NODE'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.setContent('<h1>ok</h1>');
  const text = await page.textContent('h1');
  await browser.close();
  if (text !== 'ok') process.exit(1);
  process.stdout.write('playwright-ok');
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
NODE
")"
[[ "${out}" == *playwright-ok* ]]

echo "ubuntu-b OK (${version})"
