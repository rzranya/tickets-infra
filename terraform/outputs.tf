output "staging_urls" {
  value = {
    tickets_api  = module.staging.tickets_api_url
    auth_service = module.staging.auth_service_url
    tickets_web  = module.staging.tickets_web_url
  }
}

output "production_urls" {
  value = {
    tickets_api  = module.production.tickets_api_url
    auth_service = module.production.auth_service_url
    tickets_web  = module.production.tickets_web_url
  }
}

output "github_actions_workload_identity_provider" {
  description = "Value for GitHub Actions' google-github-actions/auth `workload_identity_provider` input."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_actions_service_account" {
  value = google_service_account.github_deploy.email
}

output "dns_records_to_create" {
  description = "Point manual-setup-tasks.md's DNS step at these — one CNAME/A record per domain, computed by Cloud Run after apply."
  value       = merge(module.staging.dns_records, module.production.dns_records)
}
