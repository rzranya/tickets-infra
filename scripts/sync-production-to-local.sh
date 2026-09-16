#!/usr/bin/env bash
# Pulls the most recent production backup (from backup-production.sh's GCS
# bucket, or runs a fresh backup first with --fresh) down into the local
# Docker Compose Postgres, replacing whatever's there now.
#
# This is REAL customer data — names, phone numbers, payment provider
# refs — landing on your laptop's local disk. Default behavior scrubs
# buyer-identifying fields on the way in; pass --raw only if you actually
# need real names/phone/email locally (e.g. chasing a buyer-specific bug)
# and understand that's now sitting unencrypted on this machine.
#
# Usage:
#   ./scripts/sync-production-to-local.sh            # latest backup, anonymized
#   ./scripts/sync-production-to-local.sh --fresh     # take a new backup first
#   ./scripts/sync-production-to-local.sh --raw        # keep real buyer data
set -euo pipefail

BUCKET="festival-db-backups-production"
DATABASES=("festival_auth" "festival_tickets")
CONTAINER="festival-postgres"
ANONYMIZE=true
FRESH=false

for arg in "$@"; do
  case "$arg" in
    --raw) ANONYMIZE=false ;;
    --fresh) FRESH=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Error: $CONTAINER is not running. Start it with: docker compose up -d" >&2
  exit 1
fi

if [ "$FRESH" = true ]; then
  echo "Taking a fresh production backup first..."
  "$(dirname "$0")/backup-production.sh"
fi

LATEST=$(gsutil ls "gs://$BUCKET/" | sort | tail -1)
if [ -z "$LATEST" ]; then
  echo "Error: no backups found in gs://$BUCKET/. Run backup-production.sh first." >&2
  exit 1
fi
echo "Using backup: $LATEST"

WORKDIR=$(mktemp -d)
gsutil -m cp "${LATEST}"*.dump "$WORKDIR/"

echo "This will DROP and recreate: ${DATABASES[*]} on your LOCAL Postgres, then restore production data (${ANONYMIZE:+anonymized}${ANONYMIZE:-raw})."
read -r -p "Type 'yes' to continue: " confirm
[ "$confirm" = "yes" ] || { echo "Aborted."; rm -rf "$WORKDIR"; exit 1; }

for db in "${DATABASES[@]}"; do
  file="$WORKDIR/$db.dump"
  [ -f "$file" ] || { echo "Missing $file, skipping $db."; continue; }
  echo "Restoring $db..."
  docker exec "$CONTAINER" psql -U festival -d postgres -c "DROP DATABASE IF EXISTS $db;"
  docker exec "$CONTAINER" psql -U festival -d postgres -c "CREATE DATABASE $db;"
  docker exec -i "$CONTAINER" pg_restore -U festival -d "$db" < "$file"
done

rm -rf "$WORKDIR"

if [ "$ANONYMIZE" = true ]; then
  echo "Anonymizing buyer PII..."
  # festival_auth.users: real name/contact -> synthetic but stable-per-row
  # values, so the same buyer still maps to the same fake identity across
  # both databases (join on id still makes sense for testing).
  docker exec "$CONTAINER" psql -U festival -d festival_auth -c "
    UPDATE users SET
      \"firstName\" = 'Buyer',
      \"lastName\" = substr(id, 1, 8),
      email = CASE WHEN email IS NOT NULL THEN substr(id, 1, 8) || '@example.test' END,
      phone = CASE WHEN phone IS NOT NULL THEN '+66' || lpad((abs(hashtext(id)) % 900000000 + 100000000)::text, 9, '0') END,
      \"dateOfBirth\" = NULL,
      \"avatarUrl\" = NULL
    WHERE role = 'buyer';
  "
  # tickets_api's own delivery-address snapshot on Order — same treatment.
  docker exec "$CONTAINER" psql -U festival -d festival_tickets -c "
    UPDATE orders SET
      \"recipientName\" = CASE WHEN \"recipientName\" IS NOT NULL THEN 'Buyer ' || substr(id, 1, 8) END,
      \"recipientPhone\" = CASE WHEN \"recipientPhone\" IS NOT NULL THEN '+66' || lpad((abs(hashtext(id)) % 900000000 + 100000000)::text, 9, '0') END,
      \"addressLine\" = CASE WHEN \"addressLine\" IS NOT NULL THEN '123 Example Rd' END
    WHERE \"recipientName\" IS NOT NULL OR \"recipientPhone\" IS NOT NULL;
  "
fi

echo "Sync complete."
