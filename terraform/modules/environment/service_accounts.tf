# One service account per Cloud Run service — least-privilege, scoped
# below to only the secrets/Cloud SQL access each one actually needs.

resource "google_service_account" "auth_service" {
  project      = var.project_id
  account_id   = "auth-svc-${var.environment}"
  display_name = "festival-auth-service (${var.environment})"
}

resource "google_service_account" "tickets_api" {
  project      = var.project_id
  account_id   = "tickets-api-${var.environment}"
  display_name = "tickets-api (${var.environment})"
}

resource "google_service_account" "tickets_web" {
  project      = var.project_id
  account_id   = "tickets-web-${var.environment}"
  display_name = "tickets-web (${var.environment})"
}

# Cloud SQL Client — only the two backend services ever connect to
# Postgres directly (tickets-web talks to them over HTTP, not the DB).
resource "google_project_iam_member" "auth_service_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.auth_service.email}"
}

resource "google_project_iam_member" "tickets_api_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.tickets_api.email}"
}

# --- Per-secret access, not project-wide secretAccessor ---

resource "google_secret_manager_secret_iam_member" "auth_service_secrets" {
  for_each = toset([
    google_secret_manager_secret.database_url_auth.secret_id,
    google_secret_manager_secret.redis_url.secret_id,
    google_secret_manager_secret.internal_service_secret.secret_id,
    "mailgun-api-key-${var.environment}",
    "firebase-api-key-${var.environment}",
    "firebase-auth-domain-${var.environment}",
    "jwt-private-key-${var.environment}",
  ])
  project    = var.project_id
  secret_id  = each.value
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_service_account.auth_service.email}"
  depends_on = [google_secret_manager_secret.manual]
}

resource "google_secret_manager_secret_iam_member" "tickets_api_secrets" {
  for_each = toset([
    google_secret_manager_secret.database_url_tickets.secret_id,
    google_secret_manager_secret.redis_url.secret_id,
    google_secret_manager_secret.internal_service_secret.secret_id,
    google_secret_manager_secret.omise_webhook_shared_secret.secret_id,
    "omise-secret-key-${var.environment}",
    "omise-public-key-${var.environment}",
  ])
  project    = var.project_id
  secret_id  = each.value
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_service_account.tickets_api.email}"
  depends_on = [google_secret_manager_secret.manual]
}
