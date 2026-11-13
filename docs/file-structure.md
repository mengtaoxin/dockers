# File structure

This repo builds several independent Docker images ("stacks"). Each stack lives in its own top-level directory and is versioned separately.

```text
dockers/
├── docs/            # project documentation
├── scripts/         # shared build helpers for the Ubuntu-based stacks
├── .github/
│   ├── workflows/   # CI: test.yml (pull requests), publish.yml (main)
│   └── scripts/     # detect-stacks.sh (selects changed stacks)
└── <stack>/         # one image per directory
    ├── Dockerfile
    ├── VERSION      # semver, read by CI to tag the image
    ├── compose.yaml
    ├── README.md
    └── scripts/     # stack-specific build / runtime / test scripts
```

A directory counts as a stack when it contains both a `Dockerfile` and a `VERSION`.

## Stacks

| Directory | Base image | Purpose |
| --- | --- | --- |
| `hello-world/` | Alpine | Minimal image that exercises the pipeline |
| `ubuntu-a/` | Ubuntu 24.04 | Node.js 24 + process-local MySQL 8 |
| `ubuntu-b/` | Ubuntu 24.04 | Node.js 24 + preinstalled Playwright browsers |
| `github-actions-runner-a/` | official actions-runner | Ephemeral Actions runner + MySQL / filecopy (SMB) |
| `mysql-server-a/` | `mysql:8.0` (backup-tool) | MySQL 8 + phpMyAdmin compose; scheduled mysqldump backups |
| `mysql-restore-tool-a/` | `mysql:8.0` | One-shot: backup zip → mountable MySQL datadir |

## Build context

Stacks that use the shared `scripts/` are built from the **repo root** so those helpers are inside the context:

```bash
docker build -f ubuntu-a/Dockerfile .
```

`hello-world/` is self-contained and builds with its own directory as the context locally; CI still uses the repo-root context for every stack.

`mysql-server-a/` and `mysql-restore-tool-a/` also build from the **repo root** (their Dockerfiles `COPY <stack>/scripts/...`).

See [commands.md](./commands.md) for everyday commands and [testing.md](./testing.md) for the smoke tests.
