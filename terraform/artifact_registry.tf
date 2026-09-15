# One shared repo for all three services' images, tagged by service name
# (festival-auth-service, tickets-api, tickets-web) — shared across
# staging/production so an image built once and validated in staging can
# be promoted to production by tag, not rebuilt.
resource "google_artifact_registry_repository" "main" {
  project       = var.project_id
  location      = var.region
  repository_id = "festival"
  format        = "DOCKER"
  depends_on    = [google_project_service.this]
}
