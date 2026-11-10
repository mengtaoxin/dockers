# ubuntu-b

Generic Ubuntu 24.04 image for Node.js + Playwright agents / CI / E2E containers:

- Node.js 24 (pinned) + npm
- Playwright Chromium / Firefox / WebKit **browsers + OS libraries** (pinned)
- Browsers live at `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`
- `ubuntu` user with passwordless `sudo`
- Common tools: `git`, `jq`, `lsof`, `nc`, `curl`

Shared build helpers live in repo-root [`scripts/`](../scripts/). Stack-specific scripts (install-playwright, tests) are under [`scripts/`](./scripts/).

The Playwright **npm package** is not preinstalled — add matching `playwright@1.64.1` in your app so it finds the baked browsers.

```bash
cd ubuntu-b
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build -d
```

One-shot command:

```bash
docker run --rm --init --ipc=host \
  ghcr.io/<owner>/ubuntu-b:0.1.0 \
  node -e "console.log('ok')"
```

Recommended run flags (also set in `compose.yaml`): `--init` and `--ipc=host`.

Smoke test:

```bash
./scripts/test.sh
```

Image (after publish): `ghcr.io/<owner>/ubuntu-b:0.1.0`
