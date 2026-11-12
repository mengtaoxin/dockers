# github-actions-runner-a

Self-hosted GitHub Actions runner based on [`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner), with extras for CI jobs:

- `sshpass`, `smbclient`, `cifs-utils`, GitHub CLI (`gh`)
- Optional SMB/CIFS share auto-mounted at `/mnt/smb` on start
- Process-local MySQL 8 (`mysql-server`) — same first-boot init as [ubuntu-a](../ubuntu-a/)
- Official `runner` user with passwordless `sudo`

## Runner lifecycle

On start, the entrypoint brings MySQL up, then **registers → runs one job → exits** (`config.sh --ephemeral --disableupdate`). Pass a custom command to skip registration (useful for smoke tests).

Self-update is disabled so the image tag / `RUNNER_VERSION` in the Dockerfile stays authoritative. Upgrade by rebuilding or pulling a newer image tag — not by letting the container rewrite its own binaries.

Orchestration owns the next cycle. The sample Compose file uses `restart: unless-stopped` so the container re-registers after each job.

## Workdir and mounts

Default work directory is `_work` under the runner home (`/home/runner/_work`). Override with `RUNNER_WORKDIR` if you need a different mount point.

That directory must be **executable** (`exec`) and large enough for checkout + tool downloads. Docker’s default tmpfs is often `noexec` and small; mounting `_work` that way without `exec` and an adequate `size` will break checkout / `setup-node` and similar steps.

**Boundary:** this image only makes the runner runnable and the workdir configurable. Whether `_work` is tmpfs, and which cache paths to persist (`~/.npm`, pip, Go modules, Playwright, `_tool`, …), is entirely up to your Compose / orchestrator — the sample compose does not bake in stack-specific caches.

Example consumer tmpfs for a fresh workspace each job (adjust uid/gid/size for your host):

```yaml
tmpfs:
  - /home/runner/_work:uid=1001,gid=1001,mode=1777,exec,size=8g
```

## SMB mount

Set `SMB_HOST` (plus `SMB_USERNAME`, `SMB_PASSWORD`, `SMB_SHARE`) and the share is mounted at `/mnt/smb` during entrypoint, before MySQL and the runner start. When `SMB_HOST` is empty, mounting is skipped entirely. The password is passed through a `0600` credentials file, never on the command line.

Mounting CIFS requires privileges. Run the container with `--privileged`, or the narrower:

```bash
--cap-add SYS_ADMIN --cap-add DAC_READ_SEARCH --security-opt apparmor:unconfined
```

In Compose, uncomment the `privileged: true` (or `cap_add` / `security_opt`) block in `compose.yaml`. Override the mount point with `SMB_MOUNT_POINT`.

```bash
docker run --rm --privileged \
  -e MYSQL_ROOT_PASSWORD=secret \
  -e SMB_HOST=nas.example.com \
  -e SMB_USERNAME=ci \
  -e SMB_PASSWORD=secret \
  -e SMB_SHARE=build-cache \
  ghcr.io/<owner>/github-actions-runner-a:0.2.0 \
  ls /mnt/smb
```

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `GITHUB_URL` | yes (runner mode) | Org or repo URL (`https://github.com/org` or `https://github.com/org/repo`) |
| `GITHUB_PAT` | yes (runner mode) | PAT used to mint a short-lived registration / removal token |
| `MYSQL_ROOT_PASSWORD` | yes | MySQL `root` password (applied on first start) |
| `MYSQL_SCHEMA_NAME` | no | Create this schema on first start (`[A-Za-z0-9_]+`) |
| `MYSQL_BIND_ADDRESS` | no | mysqld bind address (default `127.0.0.1`) |
| `MYSQL_TEST_MODE` | no | `0` (default) normal settings; `1` speed-oriented for tests/CI |
| `RUNNER_NAME` | no | Runner name (default: container hostname) |
| `RUNNER_LABELS` | no | Extra labels (default: runner defaults) |
| `RUNNER_GROUP` | no | Runner group (default: `Default`) |
| `RUNNER_WORKDIR` | no | Work directory relative to `/home/runner` (default: `_work`) |
| `SMB_HOST` | no | SMB server host/IP. When set, the share is mounted on start |
| `SMB_USERNAME` | conditional | SMB username (required when `SMB_HOST` is set) |
| `SMB_PASSWORD` | conditional | SMB password (required when `SMB_HOST` is set) |
| `SMB_SHARE` | conditional | Share name (required when `SMB_HOST` is set) |
| `SMB_MOUNT_POINT` | no | Mount point (default `/mnt/smb`) |

```bash
cd github-actions-runner-a
export GITHUB_URL=https://github.com/<org-or-owner/repo>
export GITHUB_PAT=ghp_xxx
export MYSQL_ROOT_PASSWORD=secret
export MYSQL_SCHEMA_NAME=app
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

One-shot MySQL + command (no runner registration):

```bash
docker run --rm \
  -e MYSQL_ROOT_PASSWORD=secret \
  -e MYSQL_SCHEMA_NAME=app \
  ghcr.io/<owner>/github-actions-runner-a:0.2.0 \
  gh --version
```

Smoke test (from repo root or this directory):

```bash
./scripts/test.sh
```

Image (after publish): `ghcr.io/<owner>/github-actions-runner-a:0.2.0`
