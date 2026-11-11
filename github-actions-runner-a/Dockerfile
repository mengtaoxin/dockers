# syntax=docker/dockerfile:1
# Self-hosted GitHub Actions runner based on the official image, plus
# sshpass / smbclient / MySQL 8 / GitHub CLI for CI jobs that need them.
# Build from repo root: docker build -f github-actions-runner-a/Dockerfile .

ARG RUNNER_VERSION=2.338.2
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_DATADIR=/var/lib/mysql \
    MYSQL_BIND_ADDRESS=127.0.0.1

COPY scripts/apt-update.sh \
     github-actions-runner-a/scripts/install-deps.sh \
     github-actions-runner-a/scripts/install-mysql.sh \
     /tmp/build-scripts/
RUN chmod +x /tmp/build-scripts/*.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-deps.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-mysql.sh \
    && usermod -aG mysql runner \
    && rm -rf /tmp/build-scripts

COPY github-actions-runner-a/scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY github-actions-runner-a/scripts/mysql-ensure-ready.sh /usr/local/bin/mysql-ensure-ready
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/mysql-ensure-ready \
    && ln -sf /usr/local/bin/mysql-ensure-ready /usr/local/bin/mysql-ensure-ready.sh

EXPOSE 3306

HEALTHCHECK --interval=5s --timeout=5s --start-period=25s --retries=12 \
  CMD sudo mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="$MYSQL_ROOT_PASSWORD" ping --silent || exit 1

USER runner
WORKDIR /home/runner
ENTRYPOINT ["docker-entrypoint.sh"]
