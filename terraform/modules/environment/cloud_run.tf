# Cross-service URLs would naturally form a cycle (auth-service needs
# tickets-api's address for internal registration calls; tickets-api needs
# auth-service's address for JWKS verification). Broken by having
# tickets-api and tickets-web reference auth-service's STABLE custom
# domain (a plain string, not a Terraform dependency on the auth-service
# resource) while auth-service references tickets-api's real Cloud-Run-
# assigned .uri (a real dependency — tickets-api gets created first).
# Staging gets its own "staging."-prefixed domain rather than the
# ephemeral default *.run.app URL, for exactly the same reason.
locals {
  tickets_web_domain  = var.environment == "production" ? var.tickets_web_domain : "staging.${var.tickets_web_domain}"
  auth_service_domain = var.environment == "production" ? var.auth_service_domain : "staging.${var.auth_service_domain}"
  image_base          = "${var.region}-docker.pkg.dev/${var.project_id}/festival"
}

resource "google_cloud_run_v2_service" "tickets_api" {
  project  = var.project_id
  name     = "tickets-api-${var.environment}"
  location = var.region
  # Cloud Run services are stateless — the real data lives in Cloud SQL,
  # which already has its own environment-aware deletion_protection
  # (sql.tf). No reason to also block replacing/recreating this one.
  deletion_protection = false

  template {
    service_account = google_service_account.tickets_api.email

    # Explicit, matching what Cloud Run's API already returns by default
    # (0 = scale to zero when idle) — without this Terraform saw drift on
    # every plan since the API echoes back a scaling block we never
    # declared.
    scaling {
      min_instance_count = 0
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY" # Cloud SQL goes via the Auth Proxy volume below, not this connector
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      # Placeholder until the CI/CD pipeline pushes a real image — see the
      # lifecycle block below, which stops subsequent applies from
      # reverting whatever CI deployed.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "AUTH_JWKS_URI"
        value = "https://${local.auth_service_domain}/.well-known/jwks.json"
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url_tickets.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.redis_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "INTERNAL_SERVICE_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.internal_service_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "OMISE_WEBHOOK_SHARED_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.omise_webhook_shared_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "OMISE_SECRET_KEY"
        value_source {
          secret_key_ref {
            secret  = "omise-secret-key-${var.environment}"
            version = "latest"
          }
        }
      }
      env {
        name = "OMISE_PUBLIC_KEY"
        value_source {
          secret_key_ref {
            secret  = "omise-public-key-${var.environment}"
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  # `secret_key_ref { secret = ...secret_id }` only creates a Terraform
  # dependency on the secret CONTAINER, not on the version that actually
  # populates "latest" — without these, Cloud Run can (and, once, did) get
  # created before the version exists, failing with "Secret ... version
  # latest was not found". These force the real ordering.
  depends_on = [
    google_secret_manager_secret.manual,
    google_secret_manager_secret_version.manual_placeholder,
    google_secret_manager_secret_version.database_url_tickets,
    google_secret_manager_secret_version.redis_url,
    google_secret_manager_secret_version.internal_service_secret,
    google_secret_manager_secret_version.omise_webhook_shared_secret,
    google_project_iam_member.tickets_api_sql,
  ]
}

resource "google_cloud_run_v2_service" "auth_service" {
  project             = var.project_id
  name                = "auth-service-${var.environment}"
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.auth_service.email

    scaling {
      min_instance_count = 0
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "JWT_ISSUER"
        value = "https://${local.auth_service_domain}"
      }
      env {
        name  = "TICKETS_API_URL"
        value = google_cloud_run_v2_service.tickets_api.uri
      }
      env {
        name  = "TICKETS_WEB_URL"
        value = "https://${local.tickets_web_domain}"
      }
      # FIREBASE_AUTH_EMULATOR_HOST deliberately not set — its absence is
      # what tells firebase-admin.service.ts and /firebase-config.js to use
      # real Firebase instead of the local emulator (see app.controller.ts).
      env {
        name = "JWT_PRIVATE_KEY_PEM"
        value_source {
          secret_key_ref {
            secret  = "jwt-private-key-${var.environment}"
            version = "latest"
          }
        }
      }
      env {
        name = "FIREBASE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "firebase-api-key-${var.environment}"
            version = "latest"
          }
        }
      }
      env {
        name = "FIREBASE_AUTH_DOMAIN"
        value_source {
          secret_key_ref {
            secret  = "firebase-auth-domain-${var.environment}"
            version = "latest"
          }
        }
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url_auth.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.redis_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "INTERNAL_SERVICE_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.internal_service_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "MAILGUN_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "mailgun-api-key-${var.environment}"
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  # Same reasoning as tickets_api above.
  depends_on = [
    google_secret_manager_secret.manual,
    google_secret_manager_secret_version.manual_placeholder,
    google_secret_manager_secret_version.database_url_auth,
    google_secret_manager_secret_version.redis_url,
    google_secret_manager_secret_version.internal_service_secret,
    google_project_iam_member.auth_service_sql,
  ]
}

resource "google_cloud_run_v2_service" "tickets_web" {
  project             = var.project_id
  name                = "tickets-web-${var.environment}"
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.tickets_web.email

    scaling {
      min_instance_count = 0
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "NUXT_PUBLIC_AUTH_SERVICE_URL"
        value = "https://${local.auth_service_domain}"
      }
      env {
        name  = "NUXT_PUBLIC_TICKETS_API_URL"
        value = google_cloud_run_v2_service.tickets_api.uri
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

# Public custom domains, both environments — staging gets the same
# "staging."-prefixed domain already baked into the other services' env
# vars (local.tickets_web_domain / local.auth_service_domain above), so
# both environments are consistent. Creating the mapping doesn't require
# DNS to exist yet — it just sits unresolved until you point DNS at it
# (see manual-setup-tasks.md; the DNS records Cloud Run expects come from
# this resource's `resource_records` output after apply).
resource "google_cloud_run_domain_mapping" "tickets_web" {
  project  = var.project_id
  location = var.region
  name     = local.tickets_web_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.tickets_web.name
  }
}

resource "google_cloud_run_domain_mapping" "auth_service" {
  project  = var.project_id
  location = var.region
  name     = local.auth_service_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.auth_service.name
  }
}

# Public, unauthenticated invocation — these are consumer-facing HTTP
# services, not internal ones. Least-privilege is enforced inside each app
# (JwtAuthGuard/RolesGuard), not at the Cloud Run IAM layer.
resource "google_cloud_run_v2_service_iam_member" "tickets_api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.tickets_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "auth_service_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.auth_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "tickets_web_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.tickets_web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
