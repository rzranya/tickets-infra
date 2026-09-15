variable "project_id" {
  description = "GCP project id — festival-508622, per manual-setup-tasks.md."
  type        = string
  default     = "festival-508622"
}

variable "region" {
  description = "GCP region for all resources. asia-southeast1 (Singapore) is the closest GCP region to Thailand."
  type        = string
  default     = "asia-southeast1"
}

variable "sql_tier_staging" {
  description = "Cloud SQL machine tier for staging. db-f1-micro (shared core, 0.6GB) — cost-conscious, not sized for load testing itself; bump this before using staging to run a real on-sale load test."
  type        = string
  default     = "db-f1-micro"
}

variable "sql_tier_production" {
  description = "Cloud SQL machine tier for production. db-custom-2-7680 = 2 vCPU / 7.5GB RAM, ~$100-150/mo — reasonable starting point; Phase 6 load testing will tell us if it needs to go bigger before a real high-demand on-sale."
  type        = string
  default     = "db-custom-2-7680"
}

variable "domain_tickets_web" {
  description = "Custom domain for tickets-web (production). Staging gets \"staging.\" prefixed onto this, e.g. staging.tickets.festival.in.th."
  type        = string
  default     = "tickets.festival.in.th"
}

variable "domain_auth_service" {
  description = "Custom domain for festival-auth-service (production). Staging gets \"staging.\" prefixed onto this."
  type        = string
  default     = "accounts.festival.in.th"
}

variable "github_repo_owner" {
  description = "GitHub org/user that owns the four repos — for Workload Identity Federation's attribute condition."
  type        = string
  default     = "rzranya"
}
