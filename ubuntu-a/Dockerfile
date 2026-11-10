# syntax=docker/dockerfile:1
# Generic Ubuntu + Node.js 24 + process-local MySQL for agents / CI / app test containers.
# MySQL credentials and schema come from env at first start (see docker-entrypoint.sh).
# Build from repo root: docker build -f ubuntu-a/Dockerfile .

FROM ubuntu:24.04

ARG NODE_VERSION=24.22.2
ARG PLAYWRIGHT_VERSION=1.64.1
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_DATADIR=/var/lib/mysql \
    MYSQL_BIND_ADDRESS=127.0.0.1

COPY scripts/ /tmp/build-scripts/
COPY ubuntu-a/scripts/install-mysql.sh \
     ubuntu-a/scripts/install-playwright-deps.sh \
     /tmp/build-scripts/
RUN chmod +x /tmp/build-scripts/*.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-base.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-mysql.sh

RUN /tmp/build-scripts/install-node.sh

RUN /tmp/build-scripts/install-playwright-deps.sh

RUN EXTRA_GROUPS=mysql /tmp/build-scripts/setup-ubuntu-user.sh \
    && rm -rf /tmp/build-scripts

COPY ubuntu-a/scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY ubuntu-a/scripts/mysql-ensure-ready.sh /usr/local/bin/mysql-ensure-ready
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/mysql-ensure-ready \
    && ln -sf /usr/local/bin/mysql-ensure-ready /usr/local/bin/mysql-ensure-ready.sh

EXPOSE 3306

HEALTHCHECK --interval=5s --timeout=5s --start-period=25s --retries=12 \
  CMD sudo mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="$MYSQL_ROOT_PASSWORD" ping --silent || exit 1

USER ubuntu
WORKDIR /home/ubuntu
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
