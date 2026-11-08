# dockers

Personal collection of Docker Compose stacks. Each stack is versioned and, on update, built and pushed to GitHub Packages (GHCR).

## Layout

```text
<stack>/
  VERSION        # semver, e.g. 0.1.0
  Dockerfile
  compose.yaml
  .dockerignore
  test.sh        # build + smoke checks for CI / local
```

## Versioning and publish

1. Change the stack (Dockerfile / compose / etc.).
2. Bump `<stack>/VERSION`.
3. Push to `main` (or open a PR first).

**PR:** GitHub Actions runs tests for changed stacks.  
**main:** same tests run, then successful stacks are pushed:

- `ghcr.io/<owner>/<stack>:<version>`
- `ghcr.io/<owner>/<stack>:latest`

After the first push, open the package on GitHub and set visibility to **Public** if others need to pull it.

This repo needs a GitHub remote on `main` for the workflow to run.

## Testing

Run a stack's smoke test locally (Docker required):

```bash
./hello-world/test.sh
./nodejs-a/test.sh
```

CI detects changed stacks (or all stacks when `.github/` changes) and runs each stack's `test.sh`. Publish on `main` is gated on those tests succeeding.

## Hello World

```bash
cd hello-world
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

Image (after publish): `ghcr.io/<owner>/hello-world:0.1.0`

Local builds default `GITHUB_OWNER` to `local` when unset.

## nodejs-a

Ubuntu-based image with Node.js 24 and MySQL 8.

MySQL starts automatically on container boot and the entrypoint blocks until it is ready, so by the time the container is up (or you `docker exec` in), MySQL is already usable.

Environment variables:

| Variable | Required | Description |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | yes | MySQL `root` password |
| `MYSQL_SCHEMA_NAME` | no | Create this schema on first start |

```bash
cd nodejs-a
export MYSQL_ROOT_PASSWORD=secret
export MYSQL_SCHEMA_NAME=app
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

Image (after publish): `ghcr.io/<owner>/nodejs-a:0.1.1`
