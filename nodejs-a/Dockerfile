# syntax=docker/dockerfile:1
# Generic Ubuntu + Node.js 24 + process-local MySQL for agents / CI / app test containers.
# MySQL credentials and schema come from env at first start (see docker-entrypoint.sh).

FROM ubuntu:24.04

ARG NODE_VERSION=24.22.2
ARG PLAYWRIGHT_VERSION=1.64.1
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_DATADIR=/var/lib/mysql \
    MYSQL_BIND_ADDRESS=127.0.0.1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        git \
        jq \
        lsof \
        netcat-openbsd \
        sudo \
        mysql-server \
        xz-utils \
    && mkdir -p /var/run/mysqld \
    && chown mysql:mysql /var/run/mysqld \
    && rm -rf /var/lib/mysql/* \
    && chown mysql:mysql /var/lib/mysql \
    && usermod -d /var/lib/mysql mysql \
    && printf '%s\n' \
        '[mysqld]' \
        "bind-address = ${MYSQL_BIND_ADDRESS}" \
        "mysqlx-bind-address = ${MYSQL_BIND_ADDRESS}" \
        'skip-name-resolve' \
        > /etc/mysql/mysql.conf.d/docker.cnf

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) node_arch=x64 ;; \
      arm64) node_arch=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
      | tar -xJ -C /usr/local --strip-components=1; \
    node --version; \
    npm --version; \
    mysqld --version

# Playwright Chromium OS libraries (browser binaries installed at runtime / by the app).
RUN ok=0; \
    for i in 1 2 3 4 5; do \
      if npx --yes "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium; then ok=1; break; fi; \
      echo "playwright install-deps failed (attempt ${i}); retrying …" >&2; \
      sleep $((i * 5)); \
    done; \
    test "${ok}" = 1 \
    && rm -rf /var/lib/apt/lists/*

RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && usermod -aG sudo,mysql ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY mysql-ensure-ready.sh /usr/local/bin/mysql-ensure-ready
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/mysql-ensure-ready \
    && ln -sf /usr/local/bin/mysql-ensure-ready /usr/local/bin/mysql-ensure-ready.sh

EXPOSE 3306

HEALTHCHECK --interval=5s --timeout=5s --start-period=25s --retries=12 \
  CMD sudo mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="$MYSQL_ROOT_PASSWORD" ping --silent || exit 1

USER ubuntu
WORKDIR /home/ubuntu
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
