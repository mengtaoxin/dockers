# AGENTS.md

## What this project is

Monorepo of independent Docker images ("stacks"), one per top-level directory, built in GitHub Actions and published to GHCR. Build logic is Bash in shared `scripts/` and per-stack `<stack>/scripts/`; no application code.

## Core rules

- A stack = a top-level dir with **both** `Dockerfile` and `VERSION`; CI auto-detects it — see [file-structure](docs/file-structure.md).
- Build from the **repo root**, never the stack dir: `docker build -f <stack>/Dockerfile .`
- Bump the affected stack's semver `VERSION`; a shared `scripts/`/`.github/` change affects **all** stacks — bump each.
- Bash uses `set -euo pipefail`; shared helpers live in `scripts/`, stack-specific ones in `<stack>/scripts/`.
- No network/DNS/mirror bypasses or unbounded retries for flaky external builds — see [external-failures](docs/image-build-external-failures.md).

## Core file routing

- [file-structure.md](docs/file-structure.md) — layout & build context.
- [tech-stack.md](docs/tech-stack.md) — images, pinned versions, CI.
- [commands.md](docs/commands.md) — build, run, release.
- [testing.md](docs/testing.md) — smoke tests.
- [image-build-external-failures.md](docs/image-build-external-failures.md) — external CI failures.

## When you need to

- **Add/modify a stack**: read `docs/file-structure.md`; include `Dockerfile` + `VERSION`; build from repo root.
- **Build/run locally**: follow `docs/commands.md`.
- **Verify a change**: run `<stack>/scripts/test.sh` (hello-world: `./hello-world/test.sh`); Docker must be running.
- **Release**: bump `VERSION`, push to `main`; CI tests then publishes `:VERSION`/`:latest` — see `docs/commands.md`.
- **CI shows fetch/DNS/registry errors**: read `docs/image-build-external-failures.md`; re-run, don't commit a bypass.
- **Edit `.github/` or shared `scripts/`**: all stacks are tested; bump all their `VERSION`s.
