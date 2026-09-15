output "tickets_api_url" {
  value = google_cloud_run_v2_service.tickets_api.uri
}

output "auth_service_url" {
  value = google_cloud_run_v2_service.auth_service.uri
}

output "tickets_web_url" {
  value = google_cloud_run_v2_service.tickets_web.uri
}

output "sql_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "service_account_emails" {
  value = {
    auth_service = google_service_account.auth_service.email
    tickets_api  = google_service_account.tickets_api.email
    tickets_web  = google_service_account.tickets_web.email
  }
}

# DNS records to create for each domain, per Cloud Run's own domain
# verification — populated only after apply (Cloud Run computes these).
output "dns_records" {
  value = {
    (local.tickets_web_domain)  = google_cloud_run_domain_mapping.tickets_web.status[0].resource_records
    (local.auth_service_domain) = google_cloud_run_domain_mapping.auth_service.status[0].resource_records
    (local.tickets_api_domain)  = google_cloud_run_domain_mapping.tickets_api.status[0].resource_records
  }
}
