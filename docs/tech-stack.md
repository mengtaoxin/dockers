# Tech stack

## Images and runtime

- **Docker** with **Docker Compose** (`compose.yaml` per stack); images are published to **GHCR** (`ghcr.io`).
- Base images: **Ubuntu 24.04**, **Alpine 3.20**, and the official **`ghcr.io/actions/actions-runner`**.
- **Node.js 24**, pinned per stack via a build arg and installed from the official tarball.
- **MySQL 8**, installed from apt and run as a process inside the container.
- **Playwright 1.64.1**: `ubuntu-b` bakes the Chromium / Firefox / WebKit browsers; `ubuntu-a` installs only the Chromium OS libraries.

## Build and CI

- **GitHub Actions** on `ubuntu-24.04` runners: `test.yml` on pull requests, `publish.yml` on pushes to `main`.
- **Docker Buildx** with `docker/build-push-action`; each image is tagged with its semver `VERSION` and `latest`, then pushed to GHCR.

## Scripting

- Build and runtime logic is **Bash** (`set -euo pipefail`); **jq** emits the changed-stacks JSON in CI.
- Shared build helpers live in repo-root `scripts/`; stack-specific ones live in each `<stack>/scripts/`.
