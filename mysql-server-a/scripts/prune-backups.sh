#!/usr/bin/env bash
# Prune mysql-backup-YYYYMMdd-HHmmss.zip files under BACKUP_DIR.
# Quotas are derived from BACKUP_KEEP_COUNT and BACKUP_INTERVAL_MINUTES.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT:-100}"
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES:-60}"

if ! [[ "${BACKUP_KEEP_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "BACKUP_KEEP_COUNT must be a positive integer, got: ${BACKUP_KEEP_COUNT}" >&2
  exit 1
fi
if ! [[ "${BACKUP_INTERVAL_MINUTES}" =~ ^[1-9][0-9]*$ ]]; then
  echo "BACKUP_INTERVAL_MINUTES must be a positive integer, got: ${BACKUP_INTERVAL_MINUTES}" >&2
  exit 1
fi

K="${BACKUP_KEEP_COUNT}"
I="${BACKUP_INTERVAL_MINUTES}"

backups_per_day=$((1440 / I))
if [[ "${backups_per_day}" -lt 1 ]]; then
  backups_per_day=1
fi

# Soft per-day quotas from budget K; windows are fixed (3 recent / 4 mid / older).
recent_per_day=$(( (K * 50 / 100 + 1) / 3 ))
if [[ "${recent_per_day}" -lt 1 ]]; then recent_per_day=1; fi
if [[ "${recent_per_day}" -gt "${backups_per_day}" ]]; then recent_per_day="${backups_per_day}"; fi

mid_per_day=$(( (K * 30 / 100 + 2) / 4 ))
if [[ "${mid_per_day}" -lt 1 ]]; then mid_per_day=1; fi
if [[ "${mid_per_day}" -gt "${backups_per_day}" ]]; then mid_per_day="${backups_per_day}"; fi

older_per_day=1

today="$(date +%Y%m%d)"
# Epoch-ish day numbers via date for window math (portable: GNU/BusyBox date -d).
today_epoch="$(date -d "${today}" +%s 2>/dev/null || date -j -f "%Y%m%d" "${today}" +%s)"
recent_cutoff_epoch=$((today_epoch - 2 * 86400)) # today and previous 2 days => 3 calendar days
mid_cutoff_epoch=$((today_epoch - 6 * 86400))    # days 4–7 inclusive from today

shopt -s nullglob
files=("${BACKUP_DIR}"/mysql-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].zip)
if [[ "${#files[@]}" -eq 0 ]]; then
  exit 0
fi

# Sort newest first by filename timestamp.
mapfile -t sorted < <(printf '%s\n' "${files[@]}" | sort -r)

declare -A day_kept_count
keep_list=()

for path in "${sorted[@]}"; do
  base="$(basename "${path}")"
  # mysql-backup-YYYYMMdd-HHmmss.zip
  day="${base:13:8}"
  day_epoch="$(date -d "${day}" +%s 2>/dev/null || date -j -f "%Y%m%d" "${day}" +%s)"

  if [[ "${day_epoch}" -ge "${recent_cutoff_epoch}" ]]; then
    limit="${recent_per_day}"
  elif [[ "${day_epoch}" -ge "${mid_cutoff_epoch}" ]]; then
    limit="${mid_per_day}"
  else
    limit="${older_per_day}"
  fi

  count="${day_kept_count[${day}]:-0}"
  if [[ "${count}" -lt "${limit}" ]]; then
    keep_list+=("${path}")
    day_kept_count["${day}"]=$((count + 1))
  else
    echo "prune: remove (over per-day quota): ${base}"
    rm -f "${path}"
  fi
done

# Hard cap: if still over K, drop oldest survivors.
if [[ "${#keep_list[@]}" -gt "${K}" ]]; then
  mapfile -t keep_oldest_first < <(printf '%s\n' "${keep_list[@]}" | sort)
  excess=$((${#keep_oldest_first[@]} - K))
  for ((i = 0; i < excess; i++)); do
    path="${keep_oldest_first[$i]}"
    echo "prune: remove (over BACKUP_KEEP_COUNT=${K}): $(basename "${path}")"
    rm -f "${path}"
  done
fi
