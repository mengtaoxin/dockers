# ubuntu-a

Generic Ubuntu 24.04 image for Node.js agents / CI / app test containers:

- Node.js 24 (pinned) + npm
- Process-local MySQL 8 (`mysql-server`)
- `ubuntu` user with passwordless `sudo`
- Common tools: `git`, `jq`, `lsof`, `nc`, `curl`
- Playwright Chromium **OS libraries** (browser binaries still installed at runtime)

MySQL is started by `mysql-ensure-ready` (also the image `ENTRYPOINT`) before the container command runs. Credentials are **not** baked into the image; pass them as env on first start (empty datadir).

Environment variables:

| Variable | Required | Description |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | yes | MySQL `root` password (applied on first start) |
| `MYSQL_SCHEMA_NAME` | no | Create this schema on first start (`[A-Za-z0-9_]+`) |
| `MYSQL_BIND_ADDRESS` | no | mysqld bind address (default `127.0.0.1`; compose sets `0.0.0.0` for published ports) |

```bash
cd ubuntu-a
export MYSQL_ROOT_PASSWORD=secret
export MYSQL_SCHEMA_NAME=app
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

One-shot command (MySQL is up before `node` runs):

```bash
docker run --rm \
  -e MYSQL_ROOT_PASSWORD=secret \
  -e MYSQL_SCHEMA_NAME=app \
  ghcr.io/<owner>/ubuntu-a:0.2.0 \
  node -e "console.log('ok')"
```

Cloud / host `start` hooks can call the same helper idempotently:

```bash
export MYSQL_ROOT_PASSWORD=secret
export MYSQL_SCHEMA_NAME=app
mysql-ensure-ready
```

Image (after publish): `ghcr.io/<owner>/ubuntu-a:0.2.0`
