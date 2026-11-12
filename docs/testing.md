# Testing

There is no language-level test framework. Each stack ships a Bash smoke test that builds the image and checks it inside real containers.

## Test script location

CI looks for the script in this order:

1. `<stack>/scripts/test.sh`
2. `<stack>/test.sh`

`hello-world` keeps it at the stack root; the other stacks keep it under `scripts/`.

## Running locally

Docker must be running. The scripts resolve their own paths, so they can be invoked from any directory:

```bash
./hello-world/test.sh
./ubuntu-a/scripts/test.sh
./ubuntu-b/scripts/test.sh
./github-actions-runner-a/scripts/test.sh
```

Each script builds a local `dockers-test/<stack>:test` image, starts containers, and asserts the expected tools and services work. It exits non-zero on the first failure.

## In CI

- **Pull request** (`test.yml`): only stacks changed in the PR are tested.
- **Push to `main`** (`publish.yml`): changed stacks are tested, and only passing stacks are published.
- A change under `.github/` or the shared `scripts/` triggers a test of **all** stacks.

Which stacks are tested is decided by `.github/scripts/detect-stacks.sh` (any directory containing both a `Dockerfile` and a `VERSION`). Both workflows can also be triggered manually via `workflow_dispatch`.
