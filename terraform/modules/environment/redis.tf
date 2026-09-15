# Basic tier (no HA/failover) for both environments — Redis here only ever
# holds checkout holds and rate-limit counters, nothing that needs to
# survive a failover un-lost. Worth reconsidering STANDARD_HA for
# production before a real launch, same spirit as the Cloud SQL tier split
# (see variables.tf's sql_tier_production) — not done here yet since it
# wasn't asked for.
resource "google_redis_instance" "main" {
  project        = var.project_id
  name           = "festival-${var.environment}"
  region         = var.region
  tier           = "BASIC"
  memory_size_gb = 1
  redis_version  = "REDIS_7_0"

  # Memorystore's API wants the explicit "projects/.../global/networks/..."
  # form, not whatever format google_compute_network.id happens to resolve
  # to on this provider version — the first apply failed with "Invalid
  # project resource name" passing network_id straight through.
  authorized_network = "projects/${var.project_id}/global/networks/${var.network_name}"
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  depends_on = [var.private_vpc_connection]
}

resource "google_secret_manager_secret" "redis_url" {
  project   = var.project_id
  secret_id = "redis-url-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_url" {
  secret      = google_secret_manager_secret.redis_url.id
  secret_data = "redis://${google_redis_instance.main.host}:${google_redis_instance.main.port}"
}
