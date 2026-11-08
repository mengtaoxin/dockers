#!/usr/bin/env bash
# Emit a JSON array of publishable stacks changed between two commits.
# Usage: detect-stacks.sh <before_sha> <after_sha>
# If before is empty/all-zeros, or .github/ changed, list all stacks.
set -euo pipefail

list_stacks() {
  for dir in */; do
    name="${dir%/}"
    if [[ -f "${name}/Dockerfile" && -f "${name}/VERSION" ]]; then
      printf '%s\n' "${name}"
    fi
  done | sort
}

before="${1:-}"
after="${2:-HEAD}"

stacks=""
if [[ -z "${before}" || "${before}" =~ ^0+$ ]]; then
  stacks="$(list_stacks)"
elif git diff --name-only "${before}" "${after}" | grep -qE '^\.github/'; then
  stacks="$(list_stacks)"
else
  changed="$(git diff --name-only "${before}" "${after}" | awk -F/ 'NF>1 {print $1}' | sort -u)"
  for name in ${changed}; do
    if [[ -f "${name}/Dockerfile" && -f "${name}/VERSION" ]]; then
      stacks="${stacks}${stacks:+$'\n'}${name}"
    fi
  done
fi

if [[ -z "${stacks}" ]]; then
  echo "[]"
  exit 0
fi

printf '%s\n' "${stacks}" | jq -R . | jq -cs .
