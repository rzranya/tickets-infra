# Every API this config (or the services it deploys) needs enabled.
# Enabling here rather than manually in Console keeps it reproducible and
# reviewable — this is exactly the kind of "before any GCP deploy" step
# manual-setup-tasks.md marks as fair to delegate to Terraform once the
# project/billing exist (they do — see festival-508622).
locals {
  required_apis = [
    "run.googleapis.com",               # Cloud Run
    "sqladmin.googleapis.com",          # Cloud SQL
    "redis.googleapis.com",             # Memorystore
    "secretmanager.googleapis.com",     # Secret Manager
    "artifactregistry.googleapis.com",  # Container image storage for Cloud Run
    "vpcaccess.googleapis.com",         # Serverless VPC Access (Cloud Run -> Memorystore)
    "servicenetworking.googleapis.com", # Private services access (Memorystore needs this)
    "compute.googleapis.com",           # VPC network/subnet
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # Workload Identity Federation
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.required_apis)
  project  = var.project_id
  service  = each.value

  disable_dependent_services = false
  # Never disable an API on `terraform destroy` — a shared project like
  # this one may have other things depending on it we don't know about.
  disable_on_destroy = false
}
