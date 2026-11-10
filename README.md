# dockers

Personal collection of Docker Compose stacks. Each stack is versioned and, on update, built and pushed to GitHub Packages (GHCR).

## Layout

```text
scripts/             # shared build helpers (install-base / install-node / setup-ubuntu-user)
<stack>/
  README.md          # stack-specific docs
  VERSION            # semver, e.g. 0.1.0
  Dockerfile         # build from repo root: docker build -f <stack>/Dockerfile .
  compose.yaml
  scripts/           # stack-specific build / runtime / test scripts
    test.sh          # build + smoke checks for CI / local (some stacks keep test.sh at stack root)
```

## Stacks

| Stack | Description |
| --- | --- |
| [hello-world](./hello-world/) | Minimal smoke-test stack |
| [ubuntu-a](./ubuntu-a/) | Ubuntu 24.04 + Node.js 24 + process-local MySQL 8 |
| [ubuntu-b](./ubuntu-b/) | Ubuntu 24.04 + Node.js 24 + Playwright browsers |

## Versioning and publish

1. Change the stack (Dockerfile / compose / etc.) or shared `scripts/`.
2. Bump `<stack>/VERSION` (shared `scripts/` changes should bump every affected stack).
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
./ubuntu-a/scripts/test.sh
./ubuntu-b/scripts/test.sh
```

CI detects changed stacks (or all stacks when `.github/` or shared `scripts/` changes) and runs each stack's test script. Publish on `main` is gated on those tests succeeding.
