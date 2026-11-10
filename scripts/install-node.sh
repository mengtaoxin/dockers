#!/usr/bin/env bash
# Install a pinned Node.js binary from nodejs.org for TARGETARCH.
set -euo pipefail

: "${NODE_VERSION:?NODE_VERSION is required}"
: "${TARGETARCH:?TARGETARCH is required}"

case "${TARGETARCH}" in
  amd64) node_arch=x64 ;;
  arm64) node_arch=arm64 ;;
  *)
    echo "unsupported TARGETARCH=${TARGETARCH}" >&2
    exit 1
    ;;
esac

curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
  | tar -xJ -C /usr/local --strip-components=1

node --version
npm --version
