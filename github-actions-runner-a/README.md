# github-actions-runner-a

Self-hosted GitHub Actions runner based on [`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner), with extras for CI jobs:

- `sshpass`, `smbclient`, GitHub CLI (`gh`)
- Process-local MySQL 8 (`mysql-server`) — same first-boot init as [ubuntu-a](../ubuntu-a/)
- Official `runner` user with passwordless `sudo`

On start, the entrypoint brings MySQL up, then registers (or reuses) the runner via `GITHUB_URL` + `GITHUB_PAT` and runs `./run.sh`. Pass a custom command to skip registration (useful for smoke tests).

Environment variables:

| Variable | Required | Description |
| --- | --- | --- |
| `GITHUB_URL` | yes (runner mode) | Org or repo URL (`https://github.com/org` or `https://github.com/org/repo`) |
| `GITHUB_PAT` | yes (runner mode) | PAT used to mint a short-lived registration / removal token |
| `MYSQL_ROOT_PASSWORD` | yes | MySQL `root` password (applied on first start) |
| `MYSQL_SCHEMA_NAME` | no | Create this schema on first start (`[A-Za-z0-9_]+`) |
| `MYSQL_BIND_ADDRESS` | no | mysqld bind address (default `127.0.0.1`) |
| `MYSQL_TEST_MODE` | no | `0` (default) normal settings; `1` speed-oriented for tests/CI |

Optional runner knobs: `RUNNER_NAME`, `RUNNER_LABELS`, `RUNNER_GROUP` (default `Default`).

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
  ghcr.io/<owner>/github-actions-runner-a:0.1.0 \
  gh --version
```

Smoke test (from repo root or this directory):

```bash
./scripts/test.sh
```

Image (after publish): `ghcr.io/<owner>/github-actions-runner-a:0.1.0`
