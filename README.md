# dockers

Personal collection of Docker Compose stacks. Each stack is versioned and, on update, built and pushed to GitHub Packages (GHCR).

## Layout

```text
<stack>/
  README.md      # stack-specific docs
  VERSION        # semver, e.g. 0.1.0
  Dockerfile
  compose.yaml
  .dockerignore
  test.sh        # build + smoke checks for CI / local
```

## Stacks

| Stack | Description |
| --- | --- |
| [hello-world](./hello-world/) | Minimal smoke-test stack |
| [ubuntu-a](./ubuntu-a/) | Ubuntu 24.04 + Node.js 24 + process-local MySQL 8 |

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
./ubuntu-a/test.sh
```

CI detects changed stacks (or all stacks when `.github/` changes) and runs each stack's `test.sh`. Publish on `main` is gated on those tests succeeding.
