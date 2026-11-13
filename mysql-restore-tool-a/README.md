# mysql-restore-tool-a

One-shot tool that turns a `mysql-server-a` backup zip into a **mountable MySQL 8.0 datadir**.

It does **not** join the server compose and never touches a live `./data` directory. Point it at the same `./backup` folder the server uses.

## How it works

1. Unzip `mysql-backup-YYYYMMdd-HHmmss.zip` (expects `dump.sql` from `mysqldump --all-databases`).
2. Start a temporary `mysqld` with an empty datadir.
3. Import the SQL dump; shut down cleanly.
4. Write the resulting datadir next to the zip as `./backup/mysql-backup-YYYYMMdd-HHmmss/` (adds a random suffix if that path already exists).

## Run

```bash
# Share the server stack's backup directory
docker run --rm \
  -v /path/to/mysql-server-a/backup:/backup \
  ghcr.io/<owner>/mysql-restore-tool-a:0.1.0 \
  --file mysql-backup-20260101-120000.zip
```

Or from this directory (build from repo root via compose `context: ..`):

```bash
cd mysql-restore-tool-a
mkdir -p backup
# copy or mount the zip into ./backup first
VERSION=$(tr -d '[:space:]' < VERSION) \
  docker compose run --rm restore --file mysql-backup-20260101-120000.zip
```

Then start MySQL with the new folder as the datadir, for example:

```bash
docker run --rm \
  -e MYSQL_ROOT_PASSWORD=secret \
  -v /path/to/backup/mysql-backup-20260101-120000:/var/lib/mysql \
  mysql:8.0
```

Use the **same major version** (`mysql:8.0`) as the dump source.

## Build

From the **repo root**:

```bash
docker build -f mysql-restore-tool-a/Dockerfile -t mysql-restore-tool-a:local .
```
