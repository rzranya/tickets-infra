#!/usr/bin/env bash
# Backup/restore for the two local Postgres databases (festival_auth,
# festival_tickets) running in the festival-postgres container (see
# ../docker-compose.yml). This is the local dry run for Phase 6's backup/
# restore drill — the real drill against Cloud SQL reuses the same
# pg_dump/pg_restore logic once that instance exists (Slice B).
set -euo pipefail

CONTAINER="festival-postgres"
DATABASES=("festival_auth" "festival_tickets")
BACKUP_DIR="${BACKUP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/backups}"

usage() {
  echo "Usage: $0 backup [backup-dir]"
  echo "       $0 restore <backup-dir> [--yes]"
  exit 1
}

require_container() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Error: $CONTAINER is not running. Start it with: docker compose up -d" >&2
    exit 1
  fi
}

do_backup() {
  require_container
  local dir="${2:-$BACKUP_DIR}"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  local out="$dir/$stamp"
  mkdir -p "$out"
  for db in "${DATABASES[@]}"; do
    echo "Dumping $db..."
    docker exec "$CONTAINER" pg_dump -U festival -Fc "$db" > "$out/$db.dump"
  done
  echo "Backup written to $out"
}

do_restore() {
  require_container
  local dir="${2:-}"
  [ -z "$dir" ] && usage
  if [ "${3:-}" != "--yes" ]; then
    echo "This will DROP and recreate: ${DATABASES[*]}, then restore from $dir."
    read -r -p "Type 'yes' to continue: " confirm
    [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }
  fi
  for db in "${DATABASES[@]}"; do
    local file="$dir/$db.dump"
    if [ ! -f "$file" ]; then
      echo "Missing $file, skipping $db."
      continue
    fi
    echo "Restoring $db from $file..."
    docker exec "$CONTAINER" psql -U festival -d postgres -c "DROP DATABASE IF EXISTS $db;"
    docker exec "$CONTAINER" psql -U festival -d postgres -c "CREATE DATABASE $db;"
    docker exec -i "$CONTAINER" pg_restore -U festival -d "$db" < "$file"
  done
  echo "Restore complete."
}

cmd="${1:-}"
case "$cmd" in
  backup) do_backup "$@" ;;
  restore) do_restore "$@" ;;
  *) usage ;;
esac
