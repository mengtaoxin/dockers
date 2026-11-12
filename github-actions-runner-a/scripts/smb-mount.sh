#!/usr/bin/env bash
# Mount an SMB/CIFS share at container start.
#
# Mounting is enabled only when SMB_HOST is set; in that case SMB_USERNAME,
# SMB_PASSWORD and SMB_SHARE are all required.
#
# The container must be allowed to mount CIFS — run with --privileged, or:
#   --cap-add SYS_ADMIN --cap-add DAC_READ_SEARCH --security-opt apparmor:unconfined
set -euo pipefail

: "${SMB_MOUNT_POINT:=/mnt/smb}"

if [[ -z "${SMB_HOST:-}" ]]; then
  echo "[smb-mount] SMB_HOST not set; skipping SMB mount." >&2
  exit 0
fi

if [[ -z "${SMB_USERNAME:-}" || -z "${SMB_PASSWORD:-}" || -z "${SMB_SHARE:-}" ]]; then
  echo "[smb-mount] SMB_HOST is set but SMB_USERNAME / SMB_PASSWORD / SMB_SHARE are missing" >&2
  exit 1
fi

if mountpoint -q "${SMB_MOUNT_POINT}"; then
  echo "[smb-mount] ${SMB_MOUNT_POINT} is already mounted; skipping." >&2
  exit 0
fi

sudo mkdir -p "${SMB_MOUNT_POINT}"

uid="$(id -u)"
gid="$(id -g)"

# Credentials via a file (0600) instead of the command line, so the password
# never appears in the process list or container logs.
cred_file="$(mktemp)"
chmod 600 "${cred_file}"
cat > "${cred_file}" <<EOF
username=${SMB_USERNAME}
password=${SMB_PASSWORD}
EOF
trap 'rm -f "${cred_file}"' EXIT

echo "[smb-mount] mounting //${SMB_HOST}/${SMB_SHARE} at ${SMB_MOUNT_POINT}" >&2
sudo mount -t cifs "//${SMB_HOST}/${SMB_SHARE}" "${SMB_MOUNT_POINT}" \
  -o "credentials=${cred_file},uid=${uid},gid=${gid},iocharset=utf8,noperm"

rm -f "${cred_file}"
trap - EXIT

echo "[smb-mount] mounted." >&2
