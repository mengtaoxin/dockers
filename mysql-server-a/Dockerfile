# Backup-tool image for mysql-server-a (built from repo root).
FROM mysql:8.0

USER root

RUN set -eux; \
  if command -v microdnf >/dev/null 2>&1; then \
    microdnf install -y zip unzip findutils && microdnf clean all; \
  elif command -v apt-get >/dev/null 2>&1; then \
    apt-get update; \
    apt-get install -y --no-install-recommends zip unzip; \
    rm -rf /var/lib/apt/lists/*; \
  else \
    echo "unsupported base image: need microdnf or apt-get" >&2; \
    exit 1; \
  fi

COPY mysql-server-a/scripts/backup-loop.sh /usr/local/bin/backup-loop.sh
COPY mysql-server-a/scripts/prune-backups.sh /usr/local/bin/prune-backups.sh
RUN chmod +x /usr/local/bin/backup-loop.sh /usr/local/bin/prune-backups.sh

# Do not start mysqld; this image only runs the backup loop.
ENTRYPOINT ["/usr/local/bin/backup-loop.sh"]
