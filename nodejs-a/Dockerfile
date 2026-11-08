# syntax=docker/dockerfile:1

FROM ubuntu:24.04

ARG NODE_VERSION=24.22.2
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_DATADIR=/var/lib/mysql

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        mysql-server \
        xz-utils \
    && mkdir -p /var/run/mysqld \
    && chown mysql:mysql /var/run/mysqld \
    && rm -rf /var/lib/mysql/* \
    && chown mysql:mysql /var/lib/mysql \
    && printf '[mysqld]\nbind-address = 0.0.0.0\nmysqlx-bind-address = 0.0.0.0\nskip-name-resolve\n' \
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

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 3306

VOLUME ["/var/lib/mysql"]

HEALTHCHECK --interval=5s --timeout=5s --start-period=20s --retries=12 \
  CMD mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="$MYSQL_ROOT_PASSWORD" ping --silent || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mysqld"]
