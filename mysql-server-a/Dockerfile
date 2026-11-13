# syntax=docker/dockerfile:1
# All-in-one MySQL 8 + phpMyAdmin + scheduled backup on Ubuntu 24.04.
# Build from repo root: docker build -f mysql-server-a/Dockerfile .

FROM ubuntu:24.04

ARG PHPMYADMIN_VERSION=5.2.3
ARG STACK_VERSION=0.3.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_DATADIR=/var/lib/mysql \
    MYSQL_BIND_ADDRESS=0.0.0.0 \
    BACKUP_DIR=/backup \
    BACKUP_TOOL_VERSION=${STACK_VERSION} \
    TZ=UTC

COPY scripts/ /tmp/build-scripts/
COPY mysql-server-a/scripts/install-mysql.sh \
     mysql-server-a/scripts/install-phpmyadmin.sh \
     /tmp/build-scripts/
RUN chmod +x /tmp/build-scripts/*.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build-scripts/install-base.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    MYSQL_BIND_ADDRESS=0.0.0.0 /tmp/build-scripts/install-mysql.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    PHPMYADMIN_VERSION=${PHPMYADMIN_VERSION} /tmp/build-scripts/install-phpmyadmin.sh \
    && rm -rf /tmp/build-scripts

COPY mysql-server-a/mysql/conf.d/zz-logging.cnf /etc/mysql/mysql.conf.d/zz-logging.cnf
COPY mysql-server-a/apache/phpmyadmin.conf /etc/apache2/sites-available/phpmyadmin.conf
RUN a2ensite phpmyadmin >/dev/null \
    && a2dissite 000-default >/dev/null 2>&1 || true

COPY mysql-server-a/scripts/mysql-ensure-ready.sh /usr/local/bin/mysql-ensure-ready
COPY mysql-server-a/scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY mysql-server-a/scripts/backup-loop.sh /usr/local/bin/backup-loop.sh
COPY mysql-server-a/scripts/prune-backups.sh /usr/local/bin/prune-backups.sh
RUN chmod +x \
      /usr/local/bin/mysql-ensure-ready \
      /usr/local/bin/docker-entrypoint.sh \
      /usr/local/bin/backup-loop.sh \
      /usr/local/bin/prune-backups.sh \
    && ln -sf /usr/local/bin/mysql-ensure-ready /usr/local/bin/mysql-ensure-ready.sh \
    && mkdir -p /backup /logs \
    && chown mysql:mysql /logs

EXPOSE 3306 80

HEALTHCHECK --interval=5s --timeout=5s --start-period=40s --retries=12 \
  CMD mysqladmin --socket=/var/run/mysqld/mysqld.sock --user=root --password="$MYSQL_ROOT_PASSWORD" ping --silent || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
