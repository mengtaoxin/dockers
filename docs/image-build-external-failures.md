# Image builds: don't paper over external failures

## Why this exists

Images are built in GitHub Actions and depend on infrastructure outside this repo: runner networking/DNS, Ubuntu mirrors, PPAs, the GHCR registry, and Actions itself. Failures there — `Could not resolve 'archive.ubuntu.com'`, `Failed to fetch`, mirror timeouts — can look like an image bug even when the Dockerfile and scripts are unchanged and previously succeeded.

Such failures are usually **external and temporary**.

## What the build already does

Install scripts fail loudly instead of trusting exit codes alone:

- `scripts/apt-update.sh` retries `apt-get update` a bounded number of times with backoff and treats `Failed to fetch` / `Could not resolve` output as a hard failure, because apt can exit 0 even when every mirror failed.
- The Playwright install scripts retry their downloads a bounded number of times.

These retries smooth over brief mirror flakiness, but after the bounded attempts the build still fails. They are not a reason to keep adding tolerance.

## What not to add

Do not commit structural bypasses that reroute the build around a specific outage:

- `docker build --network=host`, alternate DNS, or mirror rewriting
- Special-casing a runner OS/image for a one-off incident
- Silent or unbounded retry loops that hide whether the build truly succeeded

These encode someone else's outage into the tree, add surface area, and make a real packaging bug indistinguishable from flaky infrastructure. A `--network=host` bypass was tried during a DNS incident and reverted for exactly this reason.

## What to do

1. When CI fails, decide whether it is **ours** (bad package name or script) or **external** (resolve / fetch / registry / runner).
2. Fix it normally when it is ours.
3. For an external failure, re-run the workflow once the environment recovers (or use `workflow_dispatch`). Do not land a bypass "just for this run".
