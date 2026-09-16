#!/usr/bin/env bash
# Backs up both production databases (festival_auth, festival_tickets) to
# the private GCS bucket created in terraform/modules/environment/
# db_backups.tf ("festival-db-backups-production"). Production only, on
# purpose — staging/local data isn't worth this.
#
# Requires:
#   - gcloud CLI, authenticated as a principal with Cloud SQL Client +
#     Storage Object Admin on this project (your own `gcloud auth login`
#     account is enough if you're a project Owner/Editor)
#   - cloud-sql-proxy (https://cloud.google.com/sql/docs/postgres/sql-proxy)
#     — this script downloads it to /tmp if missing
#   - The production `festival` Postgres user's password (from Secret
#     Manager: `gcloud secrets versions access latest
#     --secret=database-url-tickets-production` etc. — see HANDOFF.md's
#     "Database access" section for the exact commands). Pass it via
#     PGPASSWORD, never hardcode it in this file.
#
# Usage:
#   PGPASSWORD='...' ./scripts/backup-production.sh
set -euo pipefail

PROJECT_ID="festival-508622"
REGION="asia-southeast1"
CONNECTION_NAME="${PROJECT_ID}:${REGION}:festival-production"
BUCKET="festival-db-backups-production"
DATABASES=("festival_auth" "festival_tickets")
PROXY_PORT=15432
PROXY_BIN="/tmp/cloud-sql-proxy"

if [ -z "${PGPASSWORD:-}" ]; then
  echo "Error: set PGPASSWORD to the production 'festival' DB user's password first." >&2
  echo "  See HANDOFF.md's Database access section for how to fetch it." >&2
  exit 1
fi

if [ ! -x "$PROXY_BIN" ]; then
  echo "Downloading cloud-sql-proxy..."
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  [ "$ARCH" = "x86_64" ] && ARCH="amd64"
  [ "$ARCH" = "arm64" ] && ARCH="arm64"
  curl -sL -o "$PROXY_BIN" \
    "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.${OS}.${ARCH}"
  chmod +x "$PROXY_BIN"
fi

echo "Starting Cloud SQL Auth Proxy for $CONNECTION_NAME on port $PROXY_PORT..."
"$PROXY_BIN" --port "$PROXY_PORT" "$CONNECTION_NAME" &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT
sleep 3

STAMP=$(date +%Y%m%d-%H%M%S)
WORKDIR=$(mktemp -d)

for db in "${DATABASES[@]}"; do
  echo "Dumping $db..."
  PGPASSWORD="$PGPASSWORD" pg_dump -h 127.0.0.1 -p "$PROXY_PORT" -U festival -Fc "$db" > "$WORKDIR/$db.dump"
done

echo "Uploading to gs://$BUCKET/$STAMP/..."
gsutil -m cp "$WORKDIR"/*.dump "gs://$BUCKET/$STAMP/"

rm -rf "$WORKDIR"
echo "Done. Backup at gs://$BUCKET/$STAMP/"
