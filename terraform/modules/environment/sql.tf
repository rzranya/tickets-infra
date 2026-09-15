# One Cloud SQL instance per environment, two databases within it
# (festival_auth, festival_tickets) — same data-ownership split as local
# dev (see ../../../scripts/init-databases.sql), just on real Postgres
# instead of Docker Compose.

resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = "festival-${var.environment}"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = var.environment == "production"

  settings {
    tier = var.sql_tier
    # GCP now defaults new Cloud SQL instances to ENTERPRISE_PLUS edition,
    # which only accepts its own db-perf-optimized-N-* tier names — it
    # rejected both db-f1-micro and db-custom-2-7680 with "Invalid Tier
    # ... for (ENTERPRISE_PLUS) Edition" on the first apply. ENTERPRISE is
    # the classic edition that still supports the legacy tier naming used
    # here (and in variables.tf's sql_tier_staging/production).
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.environment == "production"
      start_time                     = "17:00" # ~00:00 ICT
    }

    # Small tier only supports one availability zone — no
    # availability_type = "REGIONAL" here on purpose, that needs a bigger
    # tier. Revisit alongside the sql_tier bump before a real on-sale.
  }

  depends_on = [var.private_vpc_connection]
}

resource "google_sql_database" "auth" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "festival_auth"
}

resource "google_sql_database" "tickets" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "festival_tickets"
}

resource "random_password" "sql_user" {
  length  = 32
  special = false # keeps it URL-safe for DATABASE_URL without extra escaping
}

resource "google_sql_user" "festival" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "festival"
  password = random_password.sql_user.result
}

# DATABASE_URL for each service, one per database — read these from Secret
# Manager (see secrets.tf) at deploy time, never put them in plain tfvars.
resource "google_secret_manager_secret" "database_url_auth" {
  project   = var.project_id
  secret_id = "database-url-auth-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url_auth" {
  secret      = google_secret_manager_secret.database_url_auth.id
  secret_data = "postgresql://${google_sql_user.festival.name}:${random_password.sql_user.result}@127.0.0.1/${google_sql_database.auth.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
}

resource "google_secret_manager_secret" "database_url_tickets" {
  project   = var.project_id
  secret_id = "database-url-tickets-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url_tickets" {
  secret      = google_secret_manager_secret.database_url_tickets.id
  secret_data = "postgresql://${google_sql_user.festival.name}:${random_password.sql_user.result}@127.0.0.1/${google_sql_database.tickets.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
}
