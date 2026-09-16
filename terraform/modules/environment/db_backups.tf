# Production-only durable store for scripts/backup-production.sh's
# pg_dump output — staging/local dev data isn't worth this (nothing there
# survives a `terraform destroy` intentionally anyway). Private (no public
# IAM binding, unlike the uploads bucket) since these dumps contain real
# buyer PII and payment references.
resource "google_storage_bucket" "db_backups" {
  count = var.environment == "production" ? 1 : 0

  project                     = var.project_id
  name                        = "festival-db-backups-production"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  # 30 days of daily backups is the retention window — enough to catch a
  # slow-to-notice data problem without the bucket growing unbounded.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

output "db_backups_bucket" {
  value = var.environment == "production" ? google_storage_bucket.db_backups[0].name : null
}
