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

## Environment

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | yes | — | MySQL root password |
| `BACKUP_INTERVAL_MINUTES` | no | `60` | Minutes between backups |
| `BACKUP_KEEP_COUNT` | no | `100` | Max backup zip files to keep |
| `TZ` | no | `UTC` | Timezone for backup filenames |
| `MYSQL_HOST_PORT` | no | `3306` | Host port for MySQL |
| `PHPMYADMIN_HOST_PORT` | no | `8080` | Host port for phpMyAdmin |
| `VERSION` | no | `0.1.0` | Tag for the backup-tool image |
| `GITHUB_OWNER` | no | `local` | GHCR owner for the image name |

Backup files are named `mysql-backup-YYYYMMdd-HHmmss.zip` (all databases in one dump). Retention windows are fixed (last 3 days dense, days 4–7 medium, older 1/day); per-day quotas are derived from `BACKUP_KEEP_COUNT` and `BACKUP_INTERVAL_MINUTES`, then capped to `BACKUP_KEEP_COUNT`.

## Run

```bash
cd mysql-server-a
mkdir -p data logs backup
export MYSQL_ROOT_PASSWORD=secret
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
