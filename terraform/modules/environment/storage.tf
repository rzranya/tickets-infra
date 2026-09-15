# Durable storage for event cover/logo images and profile avatars —
# replaces writing to local Cloud Run disk, which never survives a new
# revision (any deploy, even a Terraform-only config change) and isn't
# even shared across multiple instances of the same revision. One bucket
# per environment, shared by both tickets-api (events) and auth-service
# (avatars) under separate path prefixes — see each service's own
# GCS_BUCKET_NAME env var and *-images.service.ts for the upload code.
resource "google_storage_bucket" "uploads" {
  project                     = var.project_id
  name                        = "${var.project_id}-uploads-${var.environment}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  # Old timestamped uploads (see the filename comment in *-images.service.ts
  # — every upload gets a fresh name, old ones are just abandoned, never
  # overwritten) would otherwise accumulate forever.
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
}

# Public read — these were served with no auth at all from Cloud Run's
# local disk before (anyone with the URL could view them), so this isn't a
# new exposure, just the same access model on durable storage instead.
resource "google_storage_bucket_iam_member" "uploads_public_read" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "uploads_tickets_api_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tickets_api.email}"
}

resource "google_storage_bucket_iam_member" "uploads_auth_service_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.auth_service.email}"
}
