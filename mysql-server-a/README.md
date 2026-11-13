# mysql-server-a

MySQL 8.0 server compose stack with phpMyAdmin and a scheduled all-databases backup tool.

| Service | Image | Role |
| --- | --- | --- |
| `mysql` | `mysql:8.0` | Database server |
| `phpmyadmin` | `phpmyadmin:5.2.3` | Web UI |
| `backup-tool` | this stack’s image | `mysqldump` loop + dynamic retention |

Bind mounts (under this directory):

- `./data` → `/var/lib/mysql`
- `./logs` → `/logs` (error log via `mysql/conf.d/logging.cnf`)
- `./backup` → `/backup` (zip backups; share with `mysql-restore-tool-a`)

Server process is still official `mysql:8.0`. Compose mounts `scripts/mysqld-entrypoint.sh` so mysqld always starts with utf8mb4, a `default-time-zone` derived from `TZ`, and optionally `mysql_native_password`.

## Environment

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | yes | — | MySQL root password |
| `MYSQL_NATIVE_PASSWORD` | no | `0` | If `1`/`true`, start mysqld with `--default-authentication-plugin=mysql_native_password`. Controls the **auth plugin**, not the root password. Default keeps MySQL 8 `caching_sha2_password`. |
| `BACKUP_INTERVAL_MINUTES` | no | `60` | Minutes between backups |
| `BACKUP_KEEP_COUNT` | no | `100` | Max backup zip files to keep |
| `TZ` | no | `UTC` | Single timezone source: backup filename timestamps **and** mysqld `--default-time-zone` (IANA name → offset, e.g. `Asia/Shanghai` → `+08:00`) |
| `MYSQL_HOST_PORT` | no | `3306` | Host port for MySQL |
| `PHPMYADMIN_HOST_PORT` | no | `8080` | Host port for phpMyAdmin |
| `VERSION` | no | stack `VERSION` | Tag for the backup-tool image |
| `GITHUB_OWNER` | no | `local` | GHCR owner for the image name |

Charset/collation are fixed (not env-switched): `--character-set-server=utf8mb4` and `--collation-server=utf8mb4_unicode_ci`.

Backup files are named `mysql-backup-YYYYMMdd-HHmmss.zip` (all databases in one dump). Retention windows are fixed (last 3 days dense, days 4–7 medium, older 1/day); per-day quotas are derived from `BACKUP_KEEP_COUNT` and `BACKUP_INTERVAL_MINUTES`, then capped to `BACKUP_KEEP_COUNT`.

## Run

```bash
cd mysql-server-a
mkdir -p data logs backup
export MYSQL_ROOT_PASSWORD=secret
# Optional: MYSQL_NATIVE_PASSWORD=1 TZ=Asia/Shanghai
VERSION=$(tr -d '[:space:]' < VERSION) docker compose up --build -d
```

phpMyAdmin: http://127.0.0.1:8080

## Build the backup-tool image alone

From the **repo root**:

```bash
docker build -f mysql-server-a/Dockerfile -t mysql-server-a:local .
```

## Restore

Use the separate [`mysql-restore-tool-a`](../mysql-restore-tool-a/) stack against the same `./backup` directory. It never joins this compose file.
