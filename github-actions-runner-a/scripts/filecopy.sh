#!/usr/bin/env bash
# Copy a local file to a remote file server without overwriting an existing file.
#
# Usage:
#   filecopy <local-file> <remote-path>
#
# Example:
#   filecopy /tmp/out.zip /home/xxx/y.zip
#
# remote-path is relative to the root of the configured share. The destination
# must not already exist: filecopy refuses to overwrite. Missing parent
# directories are created.
#
# The protocol is selected with FILE_COPY_TYPE; each protocol has a
# filecopy-<type> backend. Add a protocol by dropping in a new backend.
# Currently supported: smb
#
# Env:
#   FILE_COPY_TYPE  file server protocol (default: smb)
# SMB (FILE_COPY_TYPE=smb):
#   SMB_HOST        server host/IP
#   SMB_USERNAME    SMB username
#   SMB_PASSWORD    SMB password
#   SMB_SHARE       share name
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: filecopy <local-file> <remote-path>

Copy a local file to the file server. The remote path is relative to the
configured share root and must not already exist (overwriting is refused);
missing parent directories are created.

Examples:
  filecopy /tmp/out.zip /home/xxx/y.zip
  filecopy /tmp/out.zip y.zip

Protocol selected via FILE_COPY_TYPE (default: smb).
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

local_file="$1"
remote_path="$2"

if [[ ! -f "${local_file}" ]]; then
  echo "[filecopy] local file not found: ${local_file}" >&2
  exit 1
fi

copy_type="${FILE_COPY_TYPE:-smb}"

case "${copy_type}" in
  smb)
    exec filecopy-smb "${local_file}" "${remote_path}"
    ;;
  *)
    echo "[filecopy] unsupported FILE_COPY_TYPE: ${copy_type} (supported: smb)" >&2
    exit 2
    ;;
esac
