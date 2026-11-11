#!/usr/bin/env bash
# Run apt-get update with retries. apt often exits 0 even when every mirror
# fails (DNS / network), so treat fetch/resolve errors as hard failures.
set -euo pipefail

max_attempts="${APT_UPDATE_ATTEMPTS:-5}"
sleep_secs="${APT_UPDATE_SLEEP_SECS:-5}"

attempt=1
while (( attempt <= max_attempts )); do
  log="$(mktemp)"
  # Capture both streams; do not trust apt's exit status alone.
  set +e
  apt-get -o Acquire::Retries=3 update 2>&1 | tee "${log}"
  apt_ec="${PIPESTATUS[0]}"
  set -e

  if [[ "${apt_ec}" -eq 0 ]] \
    && ! grep -qE 'Failed to fetch|Could not resolve|Temporary failure resolving|Something wicked happened|^E: ' "${log}"; then
    rm -f "${log}"
    exit 0
  fi

  echo "apt-get update failed (attempt ${attempt}/${max_attempts}, exit=${apt_ec}); retrying in ${sleep_secs}s..." >&2
  cat "${log}" >&2 || true
  rm -f "${log}"
  if (( attempt == max_attempts )); then
    break
  fi
  sleep "${sleep_secs}"
  sleep_secs=$((sleep_secs + 5))
  attempt=$((attempt + 1))
done

echo "apt-get update failed after ${max_attempts} attempts" >&2
exit 1
