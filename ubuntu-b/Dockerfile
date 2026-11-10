# syntax=docker/dockerfile:1
# Generic Ubuntu + Node.js 24 + Playwright browsers for agents / CI / E2E containers.
# Build from repo root: docker build -f ubuntu-b/Dockerfile .

FROM ubuntu:24.04

ARG NODE_VERSION=24.22.2
ARG PLAYWRIGHT_VERSION=1.64.1
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

COPY scripts/ /tmp/build-scripts/
COPY ubuntu-b/scripts/install-playwright.sh /tmp/build-scripts/
RUN chmod +x /tmp/build-scripts/*.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-base.sh

RUN /tmp/build-scripts/install-node.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-playwright.sh

RUN /tmp/build-scripts/setup-ubuntu-user.sh \
    && rm -rf /tmp/build-scripts

USER ubuntu
WORKDIR /home/ubuntu
CMD ["sleep", "infinity"]
