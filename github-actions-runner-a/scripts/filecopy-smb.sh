#!/usr/bin/env bash
# SMB backend for filecopy: upload one file to an SMB/CIFS share with smbclient.
#
# Never overwrites: the destination is probed first and the upload aborts when
# it already exists. Missing parent directories are created. Userspace only
# (smbclient); no CIFS mount or privileged capabilities required.
#
# Env:
#   SMB_HOST       server host/IP (required)
#   SMB_USERNAME   username (required)
#   SMB_PASSWORD   password (required)
#   SMB_SHARE      share name (required)
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: filecopy-smb <local-file> <remote-path>" >&2
  exit 2
fi

local_file="$1"
remote_path="$2"

: "${SMB_HOST:?SMB_HOST is required}"
: "${SMB_USERNAME:?SMB_USERNAME is required}"
: "${SMB_PASSWORD:?SMB_PASSWORD is required}"
: "${SMB_SHARE:?SMB_SHARE is required}"

# smbclient uses backslash separators; accept POSIX-style input and convert.
remote_rel="${remote_path#/}"
remote_smb="$(printf '%s' "${remote_rel}" | tr '/' '\\')"

if [[ -z "${remote_smb}" ]]; then
  echo "[filecopy-smb] remote path must include a file name: ${remote_path}" >&2
  exit 2
fi

# Parent directory (share-root relative) for auto-creating intermediates.
if [[ "${remote_smb}" == *\\* ]]; then
  parent_smb="${remote_smb%\\*}"
else
  parent_smb=""
fi

# Credentials in a 0600 file, never on the command line / in the process list.
cred_file="$(mktemp)"
chmod 600 "${cred_file}"
printf 'username=%s\npassword=%s\n' "${SMB_USERNAME}" "${SMB_PASSWORD}" > "${cred_file}"
trap 'rm -f "${cred_file}"' EXIT

# smbclient often exits 0 even when a command fails, so callers parse SMB_OUTPUT.
SMB_OUTPUT=""
smb_batch() {
  local rc=0
  set +e
  SMB_OUTPUT="$(smbclient "//${SMB_HOST}/${SMB_SHARE}" -A "${cred_file}" -c "$1" 2>&1)"
  rc=$?
  set -e
  return "${rc}"
}

# Connection / session-level failures, independent of the targeted object.
conn_error_re='NT_STATUS_CONNECTION|NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCESS_DENIED|NT_STATUS_BAD_NETWORK_NAME|NT_STATUS_NETWORK|Connection to .* failed|Error connecting to|Unable to connect|tree connect failed|session setup failed|Could not connect'

echo "[filecopy-smb] checking ${remote_path} on //${SMB_HOST}/${SMB_SHARE}" >&2
smb_batch "allinfo \"${remote_smb}\"" || true

if printf '%s' "${SMB_OUTPUT}" | grep -qE 'NT_STATUS_OBJECT_NAME_NOT_FOUND|NT_STATUS_OBJECT_PATH_NOT_FOUND|Could not stat|No such file'; then
  : # destination absent — safe to upload
elif printf '%s' "${SMB_OUTPUT}" | grep -qE "${conn_error_re}"; then
  echo "[filecopy-smb] error while checking destination:" >&2
  printf '%s\n' "${SMB_OUTPUT}" >&2
  exit 1
else
  # Ambiguous output defaults to the safe choice: refuse, never overwrite.
  echo "[filecopy-smb] refusing to overwrite existing file: ${remote_path}" >&2
  printf '%s\n' "${SMB_OUTPUT}" >&2
  exit 1
fi

# Create missing parent directories; "already exists" (COLLISION) is expected.
if [[ -n "${parent_smb}" ]]; then
  IFS='\\' read -r -a dirs <<< "${parent_smb}"
  cur=""
  for d in "${dirs[@]}"; do
    [[ -z "${d}" ]] && continue
    if [[ -z "${cur}" ]]; then cur="${d}"; else cur="${cur}\\${d}"; fi
    smb_batch "mkdir \"${cur}\"" || true
    if printf '%s' "${SMB_OUTPUT}" | grep -q 'NT_STATUS_OBJECT_NAME_COLLISION'; then
      :
    elif printf '%s' "${SMB_OUTPUT}" | grep -qE "${conn_error_re}"; then
      echo "[filecopy-smb] failed to create directory ${cur}:" >&2
      printf '%s\n' "${SMB_OUTPUT}" >&2
      exit 1
    fi
  done
fi

echo "[filecopy-smb] uploading ${local_file} -> ${remote_path}" >&2
put_rc=0
smb_batch "put \"${local_file}\" \"${remote_smb}\"" || put_rc=$?
# Success prints "putting file <local> as <remote> ..."; anything else is a failure.
if [[ "${put_rc}" -ne 0 ]] || ! printf '%s' "${SMB_OUTPUT}" | grep -q '^putting file'; then
  echo "[filecopy-smb] upload failed:" >&2
  printf '%s\n' "${SMB_OUTPUT}" >&2
  exit 1
fi

echo "[filecopy-smb] copied to ${remote_path} on //${SMB_HOST}/${SMB_SHARE}" >&2
