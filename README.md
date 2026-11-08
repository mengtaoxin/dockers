# dockers

Personal collection of Docker Compose stacks. Each stack is versioned and, on update, built and pushed to GitHub Packages (GHCR).

## Layout

```text
<stack>/
  VERSION        # semver, e.g. 0.1.0
  Dockerfile
  compose.yaml
  .dockerignore
```

## Versioning and publish

1. Change the stack (Dockerfile / compose / etc.).
2. Bump `<stack>/VERSION`.
3. Push to `main`.

GitHub Actions detects changed stacks that have both `Dockerfile` and `VERSION`, then pushes:

- `ghcr.io/<owner>/<stack>:<version>`
- `ghcr.io/<owner>/<stack>:latest`

After the first push, open the package on GitHub and set visibility to **Public** if others need to pull it.

This repo needs a GitHub remote on `main` for the workflow to run.

## Hello World

```bash
cd hello-world
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

Image (after publish): `ghcr.io/<owner>/hello-world:0.1.0`

Local builds default `GITHUB_OWNER` to `local` when unset.
