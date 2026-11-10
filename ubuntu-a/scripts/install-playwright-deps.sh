#!/usr/bin/env bash
# Install Playwright Chromium OS libraries (browser binaries stay runtime/app-owned).
set -euo pipefail

: "${PLAYWRIGHT_VERSION:?PLAYWRIGHT_VERSION is required}"

ok=0
for i in 1 2 3 4 5; do
  if npx --yes "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium; then
    ok=1
    break
  fi
  echo "playwright install-deps failed (attempt ${i}); retrying …" >&2
  sleep $((i * 5))
done

test "${ok}" = 1
rm -rf /var/lib/apt/lists/*
