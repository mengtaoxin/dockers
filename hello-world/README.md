# Hello World

Minimal smoke-test stack for this repo's build / publish pipeline.

```bash
cd hello-world
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build
```

Image (after publish): `ghcr.io/<owner>/hello-world:0.1.0`

Local builds default `GITHUB_OWNER` to `local` when unset.
