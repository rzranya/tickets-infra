# Lets GitHub Actions deploy to Cloud Run without a static, downloadable
# service-account key sitting in GitHub Secrets — per manual-setup-tasks.md
# ("Set up Workload Identity Federation so GitHub Actions can deploy to
# Cloud Run without static service-account keys").
#
# Uses DIRECT Workload Identity Federation — roles are granted straight to
# the external identity (principalSet) rather than to an intermediate
# service account. The impersonation-based approach (grant a service
# account, then have GitHub "act as" it) kept failing in practice with
# "Permission 'iam.serviceAccounts.getAccessToken' denied" even with
# roles/iam.serviceAccountTokenCreator granted and plenty of propagation
# time — direct access skips that impersonation call entirely, so this
# whole failure category can't happen.
#
# Grants are scoped via attribute.repository_owner, NOT attribute.repository
# — GitHub's OIDC token embeds numeric owner/repo IDs into `sub` and
# `repository` now (e.g. "rzranya@845126/tickets-web@1368762557", not
# plain "rzranya/tickets-web"), which silently breaks a
# principalSet/attribute.repository/OWNER/* wildcard match — the token
# authenticates fine but every authorization check against that pattern
# fails with a permission-denied naming the exact permission, easy to
# mistake for a missing role. repository_owner is confirmed still a plain
# string (attribute_condition below already relies on it matching exactly).

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
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
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

locals {
  github_deploy_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_owner/${var.github_repo_owner}"
}

resource "google_project_iam_member" "github_deploy_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = local.github_deploy_principal
}

resource "google_project_iam_member" "github_deploy_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.github_deploy_principal
}

# Lets the deploy workflow set the Cloud Run services' own runtime service
# accounts on each deploy (`gcloud run deploy` requires this even when not
# changing it) — scoped to just those three, not every SA in the project.
resource "google_service_account_iam_member" "github_deploy_act_as_staging" {
  for_each           = module.staging.service_account_emails
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.github_deploy_principal
}

resource "google_service_account_iam_member" "github_deploy_act_as_production" {
  for_each           = module.production.service_account_emails
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.github_deploy_principal
}
