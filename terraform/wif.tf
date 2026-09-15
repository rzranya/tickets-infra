# Lets GitHub Actions deploy to Cloud Run without a static, downloadable
# service-account key sitting in GitHub Secrets — per manual-setup-tasks.md
# ("Set up Workload Identity Federation so GitHub Actions can deploy to
# Cloud Run without static service-account keys").

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Scoped to this org/user's repos AND the main branch specifically — a
  # PR build, a feature branch, or a fork can never mint a token through
  # this provider. This provider is for deploy workflows only; CI
  # (lint/test on PR) needs no GCP access at all, so restricting the whole
  # provider to main-branch pushes doesn't affect it.
  attribute_condition = "assertion.repository_owner == \"${var.github_repo_owner}\" && assertion.ref == \"refs/heads/main\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_deploy" {
  project      = var.project_id
  account_id   = "github-actions-deploy"
  display_name = "GitHub Actions deploy"
}

resource "google_project_iam_member" "github_deploy_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deploy.email}"
}

resource "google_project_iam_member" "github_deploy_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_deploy.email}"
}

# Lets the deploy SA set the Cloud Run services' own runtime service
# accounts on each deploy (`gcloud run deploy` requires this even when not
# changing it) — scoped to just those three, not every SA in the project.
resource "google_service_account_iam_member" "github_deploy_act_as_staging" {
  for_each           = module.staging.service_account_emails
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deploy.email}"
}

resource "google_service_account_iam_member" "github_deploy_act_as_production" {
  for_each           = module.production.service_account_emails
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deploy.email}"
}

resource "google_service_account_iam_member" "github_deploy_wif_binding" {
  service_account_id = google_service_account.github_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo_owner}/*"
}
