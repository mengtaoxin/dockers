#!/usr/bin/env bash
# Materialize a MySQL datadir from mysql-backup-YYYYMMdd-HHmmss.zip (mysqldump).
# Does not touch any live server ./data directory.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backup}"
MYSQL_USER_ID="${MYSQL_USER_ID:-999}"
MYSQL_GROUP_ID="${MYSQL_GROUP_ID:-999}"

usage() {
  cat <<'EOF'
Usage: restore.sh --file <mysql-backup-YYYYMMdd-HHmmss.zip>

Extracts the dump from /backup/<file>, imports it into a temporary mysqld,
then writes a mountable datadir next to the zip:

  /backup/<basename-without-.zip>/   (or …-<random> on name conflict)

Environment:
  BACKUP_DIR       Backup directory (default /backup)
  MYSQL_USER_ID    Owner uid for output datadir (default 999)
  MYSQL_GROUP_ID   Owner gid for output datadir (default 999)
EOF
}

FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${FILE}" ]]; then
  echo "--file is required" >&2
  usage >&2
  exit 1
fi

# Reject path components; only a basename under BACKUP_DIR.
if [[ "${FILE}" == *"/"* || "${FILE}" == *".."* ]]; then
  echo "file must be a basename under ${BACKUP_DIR}, got: ${FILE}" >&2
  exit 1
fi

if [[ ! "${FILE}" =~ ^mysql-backup-[0-9]{8}-[0-9]{6}\.zip$ ]]; then
  echo "file name must match mysql-backup-YYYYMMdd-HHmmss.zip, got: ${FILE}" >&2
  exit 1
fi

ZIP_PATH="${BACKUP_DIR}/${FILE}"
if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "backup not found: ${ZIP_PATH}" >&2
  exit 1
fi

BASE_NAME="${FILE%.zip}"
OUT_DIR="${BACKUP_DIR}/${BASE_NAME}"
if [[ -e "${OUT_DIR}" ]]; then
  suffix="$(tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  if [[ -z "${suffix}" ]]; then
    suffix="${RANDOM}"
  fi
  OUT_DIR="${BACKUP_DIR}/${BASE_NAME}-${suffix}"
fi

WORK="$(mktemp -d)"
DATADIR="${WORK}/datadir"
SOCKET="${WORK}/mysql.sock"
PIDFILE="${WORK}/mysql.pid"
ERRLOG="${WORK}/mysqld.err"
EXTRACT="${WORK}/extract"

cleanup() {
  if [[ -S "${SOCKET}" ]] || [[ -f "${PIDFILE}" ]]; then
    mysqladmin --socket="${SOCKET}" -uroot shutdown >/dev/null 2>&1 || true
    sleep 1
  fi
  if [[ -f "${PIDFILE}" ]]; then
    kill "$(cat "${PIDFILE}")" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

mkdir -p "${EXTRACT}" "${DATADIR}"
# mysqld drops privileges to mysql; the work tree must be writable by that user.
chown -R mysql:mysql "${WORK}"

echo "extracting ${ZIP_PATH}..."
unzip -q "${ZIP_PATH}" -d "${EXTRACT}"

DUMP=""
if [[ -f "${EXTRACT}/dump.sql" ]]; then
  DUMP="${EXTRACT}/dump.sql"
else
  mapfile -t sqls < <(find "${EXTRACT}" -type f -name '*.sql' | sort)
  if [[ "${#sqls[@]}" -eq 1 ]]; then
    DUMP="${sqls[0]}"
  else
    echo "expected dump.sql (or exactly one .sql) inside the zip" >&2
    find "${EXTRACT}" -type f >&2 || true
    exit 1
  fi
fi

echo "initializing temporary datadir..."
mysqld --initialize-insecure --datadir="${DATADIR}" --user=mysql

echo "starting temporary mysqld..."
mysqld \
  --datadir="${DATADIR}" \
  --user=mysql \
  --socket="${SOCKET}" \
  --pid-file="${PIDFILE}" \
  --port=0 \
  --skip-networking \
  --log-error="${ERRLOG}" &

ready=0
for _ in $(seq 1 60); do
  if mysqladmin --socket="${SOCKET}" -uroot ping --silent >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "${ready}" -ne 1 ]]; then
  echo "temporary mysqld failed to become ready" >&2
  [[ -f "${ERRLOG}" ]] && cat "${ERRLOG}" >&2
  exit 1
fi

echo "importing dump..."
mysql --socket="${SOCKET}" -uroot <"${DUMP}"

echo "shutting down temporary mysqld..."
mysqladmin --socket="${SOCKET}" -uroot shutdown

# Wait until socket/pid are gone so files are consistent.
for _ in $(seq 1 60); do
  if [[ ! -S "${SOCKET}" ]] && [[ ! -f "${PIDFILE}" ]]; then
    break
  fi
  sleep 1
done

# Drop auto.cnf so a remounted clone gets a fresh server UUID.
rm -f "${DATADIR}/auto.cnf"

mkdir -p "${OUT_DIR}"
# Move contents into the final directory (OUT_DIR is empty / newly created).
shopt -s dotglob nullglob
mv "${DATADIR}"/* "${OUT_DIR}/"
shopt -u dotglob nullglob

chown -R "${MYSQL_USER_ID}:${MYSQL_GROUP_ID}" "${OUT_DIR}"

echo "restored datadir ready: ${OUT_DIR}"
echo "Mount it as /var/lib/mysql on a mysql:8.0 container (same major version)."
