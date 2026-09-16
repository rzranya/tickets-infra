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

variable "ga_measurement_id" {
  description = "Google Analytics 4 measurement ID (e.g. \"G-XXXXXXX\") for tickets-web. Wired into production only — staging traffic (our own testing) would otherwise pollute the real analytics stream. Empty disables it entirely (see app/plugins/analytics.client.ts, which no-ops without one)."
  type        = string
  default     = "G-CZXCQ2RM5D"
}

variable "jwt_access_token_ttl_seconds" {
  description = "How long a buyer/owner/staff/admin sign-in JWT stays valid (auth-service's TokenService) before it needs the sliding renewal (see festival-auth-service's /users/me/renew-session and each frontend's auth boot plugin) to refresh it — in practice this is only how long a SIGNED-OUT-AND-NEVER-RETURNED session survives, since any visit within the window resets the clock. 7 days, matching the expectation set by musicfestival.in.th (this project's sister site) that a user shouldn't have to keep re-logging in. Same value for both environments; no reason for them to differ."
  type        = number
  default     = 604800
}

variable "domain_auth_service" {
  description = "Custom domain for festival-auth-service (production). Staging gets \"staging.\" prefixed onto this."
  type        = string
  default     = "accounts.festival.in.th"
}

variable "domain_tickets_api" {
  description = "Custom domain for tickets-api (production) — serves both the general JSON API and uploaded image/file URLs, on one domain, reached cross-origin (CORS) from tickets-web rather than through path-based routing behind a load balancer (would need its own static IP/URL map/managed cert and a flat ~$20/mo forwarding rule regardless of traffic — not worth it at this project's scale). Staging gets \"staging.\" prefixed onto this. Exists so URLs never expose the raw *.run.app hostname — that string bakes in both the GCP project number and the literal word \"staging\"/\"production\"."
  type        = string
  default     = "api.festival.in.th"
}

variable "github_repo_owner" {
  description = "GitHub org/user that owns the four repos — for Workload Identity Federation's attribute condition."
  type        = string
  default     = "rzranya"
}
