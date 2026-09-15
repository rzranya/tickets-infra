#!/usr/bin/env bash
# Manually pause/resume staging's Cloud SQL instance to save cost between
# testing sessions. Cloud Run already costs ~nothing when idle (scales to
# zero automatically, no change needed there). Memorystore/Redis has no
# stop/start state at all — the only way to stop paying for it is deleting
# and recreating the instance, which isn't worth automating for something
# this cheap (~$3-5/mo at Basic 1GB).
#
# Cloud SQL, stopped, still bills for storage (not compute) — this is
# meaningfully cheaper, not free.
set -euo pipefail

PROJECT="festival-508622"
INSTANCE="festival-staging"

usage() {
  echo "Usage: $0 stop|start|status"
  exit 1
}

cmd="${1:-}"
case "$cmd" in
  stop)
    gcloud sql instances patch "$INSTANCE" --project="$PROJECT" --activation-policy=NEVER
    ;;
  start)
    gcloud sql instances patch "$INSTANCE" --project="$PROJECT" --activation-policy=ALWAYS
    ;;
  status)
    gcloud sql instances describe "$INSTANCE" --project="$PROJECT" --format="value(settings.activationPolicy)"
    ;;
  *)
    usage
    ;;
esac
