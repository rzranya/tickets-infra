# One shared VPC for both staging and production — network-level isolation
# between them isn't critical for a project this size (separate Cloud SQL/
# Redis instances and separate service accounts/IAM already isolate the
# data and access that actually matter). Revisit if that changes.

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "festival-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.this]
}

resource "google_compute_subnetwork" "main" {
  project       = var.project_id
  name          = "festival-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

# Serverless VPC Access connector — lets Cloud Run reach Memorystore, which
# only ever exposes a private IP inside the VPC. Cloud SQL doesn't need
# this (Cloud Run connects to it via the built-in Cloud SQL Auth Proxy
# integration instead, see modules/environment/cloud_run.tf).
resource "google_vpc_access_connector" "main" {
  project       = var.project_id
  name          = "festival-connector"
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = "10.10.1.0/28"
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
  depends_on    = [google_project_service.this]
}

# Reserved IP range + private connection Memorystore needs to peer into
# this VPC (Memorystore always requires this, even at the smallest tier).
resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "festival-private-service-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
  depends_on              = [google_project_service.this]
}
