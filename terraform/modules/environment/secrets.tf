# Secrets Terraform CAN generate itself (no external account involved) —
# real random values, created here.

resource "random_password" "internal_service_secret" {
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "internal_service_secret" {
  project   = var.project_id
  secret_id = "internal-service-secret-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "internal_service_secret" {
  secret      = google_secret_manager_secret.internal_service_secret.id
  secret_data = random_password.internal_service_secret.result
}

resource "random_password" "omise_webhook_shared_secret" {
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "omise_webhook_shared_secret" {
  project   = var.project_id
  secret_id = "omise-webhook-shared-secret-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "omise_webhook_shared_secret" {
  secret      = google_secret_manager_secret.omise_webhook_shared_secret.id
  secret_data = random_password.omise_webhook_shared_secret.result
}

# --- Secrets that need a real value from an external account/console —
# Terraform only creates the slot with a placeholder. Populate for real
# with:
#   gcloud secrets versions add <secret-id> --data-file=- --project=festival-508622
# (paste the value, Ctrl-D). Never put the real value in a .tf file or
# tfvars — see manual-setup-tasks.md for where each one comes from.

locals {
  manual_secret_ids = [
    "omise-secret-key-${var.environment}",     # dashboard.omise.co, API Keys
    "omise-public-key-${var.environment}",     # same
    "mailgun-api-key-${var.environment}",      # Mailgun dashboard
    "firebase-api-key-${var.environment}",     # Firebase Console -> Project settings -> Your apps
    "firebase-auth-domain-${var.environment}", # same
    "jwt-private-key-${var.environment}",      # generate once (see festival-auth-service's KEYS_DIR comment), paste PEM
  ]
}

resource "google_secret_manager_secret" "manual" {
  for_each  = toset(local.manual_secret_ids)
  project   = var.project_id
  secret_id = each.value
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "manual_placeholder" {
  for_each = toset(local.manual_secret_ids)
  secret   = google_secret_manager_secret.manual[each.value].id
  # Placeholder only — real value goes in via `gcloud secrets versions add`,
  # not Terraform. Cloud Run will fail closed (missing/invalid credential)
  # until that's done, which is the correct failure mode, not a silent one.
  secret_data = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_data]
  }
}
