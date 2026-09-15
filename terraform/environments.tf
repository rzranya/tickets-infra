module "staging" {
  source = "./modules/environment"

  project_id             = var.project_id
  region                 = var.region
  environment            = "staging"
  sql_tier               = var.sql_tier_staging
  network_id             = google_compute_network.main.id
  network_name           = google_compute_network.main.name
  vpc_connector_id       = google_vpc_access_connector.main.id
  private_vpc_connection = google_service_networking_connection.private_vpc_connection
  tickets_web_domain     = var.domain_tickets_web
  auth_service_domain    = var.domain_auth_service
  tickets_api_domain     = var.domain_tickets_api

  depends_on = [google_artifact_registry_repository.main]
}

module "production" {
  source = "./modules/environment"

  project_id             = var.project_id
  region                 = var.region
  environment            = "production"
  sql_tier               = var.sql_tier_production
  network_id             = google_compute_network.main.id
  network_name           = google_compute_network.main.name
  vpc_connector_id       = google_vpc_access_connector.main.id
  private_vpc_connection = google_service_networking_connection.private_vpc_connection
  tickets_web_domain     = var.domain_tickets_web
  auth_service_domain    = var.domain_auth_service
  tickets_api_domain     = var.domain_tickets_api

  depends_on = [google_artifact_registry_repository.main]
}
