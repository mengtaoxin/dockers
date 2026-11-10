#!/usr/bin/env bash
# Install Playwright browser binaries and OS libraries into PLAYWRIGHT_BROWSERS_PATH.
set -euo pipefail

: "${PLAYWRIGHT_VERSION:?PLAYWRIGHT_VERSION is required}"
: "${PLAYWRIGHT_BROWSERS_PATH:=/ms-playwright}"

install -d -m 777 "${PLAYWRIGHT_BROWSERS_PATH}"

ok=0
for i in 1 2 3 4 5; do
  if npx --yes "playwright@${PLAYWRIGHT_VERSION}" install --with-deps; then
    ok=1
    break
  fi
  echo "playwright install --with-deps failed (attempt ${i}); retrying …" >&2
  sleep $((i * 5))
done

test "${ok}" = 1
chmod -R 777 "${PLAYWRIGHT_BROWSERS_PATH}"
