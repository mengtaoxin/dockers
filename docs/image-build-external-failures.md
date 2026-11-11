# Image builds: do not work around external failures

## Why this exists

Publishing images in this repo goes through GitHub Actions: build on a hosted runner, `apt-get` inside Docker, push to GHCR. That path depends on a lot of infrastructure we do not control—runner networking/DNS, Ubuntu mirrors, Launchpad PPAs, container registries, and Actions itself.

In practice those layers fail in ways that look like “our image is broken”: missing packages, `Could not resolve 'archive.ubuntu.com'`, flaky mirror timeouts. Investigating the `github-actions-runner-a` publish failures showed the pattern clearly: the same Dockerfile and install scripts that had succeeded earlier failed with pure DNS errors inside the build; the stack logic was unchanged. GitHub’s status page can still be green while a given runner’s Docker bridge DNS is unhealthy. Pinning runner images or adding retries did not fix a broken resolver—it only made the failure slower and noisier.

So the failure mode is often **external and temporary**, not a design defect in the stack.

## Why we refuse workarounds

It is tempting to “harden” the build: `docker build --network=host`, apt retry/failover ladders, mirror rewriting, alternate DNS, sleeping and looping, or special-casing runner OSes for a one-off outage.

Those patches:

- **Encode someone else’s outage into our tree.** The next reader cannot tell product intent from “survive GitHub DNS that afternoon.”
- **Add surface area** that must be maintained, tested, and explained, for a problem that usually disappears after a re-run.
- **Obscure real bugs.** If every network glitch is papered over, a genuine packaging mistake looks the same as a flaky mirror until someone digs through layers of retry logic.

This repo is a personal collection of Compose stacks, not a platform that must absorb arbitrary upstream downtime. Clarity beats clever resilience here.

## What to do instead

1. Keep Dockerfiles and install scripts **straightforward**: update, install, fail if something is wrong.
2. When CI fails, check whether the error is **ours** (bad package name, broken script) or **external** (resolve/fetch/registry/runner).
3. For external failures: **wait for the environment to recover**, then re-run the workflow (or push again). Do not land a bypass “just for this run.”
4. Still fix real bugs in our code when the failure is ours.

## What this is not

This is not a ban on clear errors, version pins that define the image, or intentional product behavior. It is a ban on **defensive complexity whose only job is to paper over transient host/upstream problems**.
