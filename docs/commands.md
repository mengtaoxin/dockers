# Commands

## Run a stack with Compose

Each `compose.yaml` reads `VERSION` (and optionally `GITHUB_OWNER`) from the environment:

```bash
cd ubuntu-a
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

`GITHUB_OWNER` defaults to `local` for local builds. Required variables (e.g. `MYSQL_ROOT_PASSWORD`, and for the runner `GITHUB_URL` / `GITHUB_PAT`) are listed in each stack's README.

## Build an image directly

Stacks that use the shared helpers must be built from the repo root:

```bash
docker build -f ubuntu-a/Dockerfile .
docker build -f github-actions-runner-a/Dockerfile .
```

## Release a new version

1. Make the change (stack files or shared `scripts/`).
2. Bump the affected stack's `VERSION` (a shared `scripts/` change bumps every affected stack).
3. Push to `main`; CI tests the stack and, on success, pushes `ghcr.io/<owner>/<stack>:<version>` and `:latest`.

## Tests

See [testing.md](./testing.md) for running smoke tests locally and in CI.
