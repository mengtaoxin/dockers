#!/usr/bin/env bash
# Start process-local MySQL, then either exec a custom command or register/run the Actions runner.
# Env (runner mode):
#   GITHUB_URL  (required)  org or repo URL, e.g. https://github.com/org or https://github.com/org/repo
#   GITHUB_PAT  (required)  PAT used to mint a short-lived registration token
# Optional:
#   RUNNER_NAME    (default: hostname)
#   RUNNER_LABELS  (default: empty — runner defaults)
#   RUNNER_GROUP   (default: Default)
#   RUNNER_WORKDIR (default: _work)
set -euo pipefail

mysql-ensure-ready

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

: "${GITHUB_URL:?GITHUB_URL is required}"
: "${GITHUB_PAT:?GITHUB_PAT is required}"

RUNNER_HOME="${RUNNER_HOME:-/home/runner}"
cd "${RUNNER_HOME}"

normalize_url() {
  local u="${1%/}"
  printf '%s' "${u}"
}

api_registration_url() {
  local github_url="$1"
  local host path api_host scheme
  github_url="$(normalize_url "${github_url}")"
  scheme="$(printf '%s' "${github_url}" | sed -E 's#^(https?)://.*#\1#')"
  host="$(printf '%s' "${github_url}" | sed -E 's#^https?://([^/]+)/.*#\1#; s#^https?://([^/]+)$#\1#')"
  path="$(printf '%s' "${github_url}" | sed -E 's#^https?://[^/]+/?##')"
  path="${path%/}"

  if [[ "${host}" == "github.com" ]]; then
    api_host="api.github.com"
  else
    api_host="${host}/api/v3"
  fi

  IFS='/' read -r -a parts <<< "${path}"
  if [[ ${#parts[@]} -eq 1 && -n "${parts[0]}" ]]; then
    printf '%s://%s/orgs/%s/actions/runners/registration-token' "${scheme}" "${api_host}" "${parts[0]}"
  elif [[ ${#parts[@]} -eq 2 ]]; then
    if [[ "${parts[0]}" == "enterprises" ]]; then
      printf '%s://%s/enterprises/%s/actions/runners/registration-token' "${scheme}" "${api_host}" "${parts[1]}"
    else
      printf '%s://%s/repos/%s/%s/actions/runners/registration-token' "${scheme}" "${api_host}" "${parts[0]}" "${parts[1]}"
    fi
  else
    echo "GITHUB_URL must be an org or repository URL: ${github_url}" >&2
    return 1
  fi
}

api_removal_url() {
  api_registration_url "$1" | sed 's/registration-token$/remove-token/'
}

fetch_token() {
  local endpoint="$1"
  local response token
  response="$(curl -fsSL -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${endpoint}")"
  token="$(printf '%s' "${response}" | jq -r '.token // empty')"
  if [[ -z "${token}" ]]; then
    echo "Failed to obtain runner token from ${endpoint}" >&2
    echo "${response}" >&2
    return 1
  fi
  printf '%s' "${token}"
}

remove_runner() {
  if [[ ! -f "${RUNNER_HOME}/.runner" ]]; then
    return 0
  fi
  echo "Removing runner registration..." >&2
  local remove_token
  if remove_token="$(fetch_token "$(api_removal_url "${GITHUB_URL}")")"; then
    ./config.sh remove --token "${remove_token}" || true
  else
    echo "Could not fetch removal token; leaving local .runner in place" >&2
  fi
}

trap remove_runner EXIT

if [[ ! -f "${RUNNER_HOME}/.runner" ]]; then
  echo "Configuring runner for ${GITHUB_URL}" >&2
  reg_token="$(fetch_token "$(api_registration_url "${GITHUB_URL}")")"
  config_args=(
    --unattended
    --url "$(normalize_url "${GITHUB_URL}")"
    --token "${reg_token}"
    --name "${RUNNER_NAME:-$(hostname)}"
    --work "${RUNNER_WORKDIR:-_work}"
    --replace
  )
  if [[ -n "${RUNNER_LABELS:-}" ]]; then
    config_args+=(--labels "${RUNNER_LABELS}")
  fi
  if [[ -n "${RUNNER_GROUP:-}" ]]; then
    config_args+=(--runnergroup "${RUNNER_GROUP}")
  fi
  ./config.sh "${config_args[@]}"
fi

exec ./run.sh
