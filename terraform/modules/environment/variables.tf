variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "\"staging\" or \"production\" — used in every resource name."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be \"staging\" or \"production\"."
  }
}

variable "sql_tier" {
  type = string
}

variable "network_id" {
  type = string
}

variable "network_name" {
  type = string
}

variable "vpc_connector_id" {
  type = string
}

variable "private_vpc_connection" {
  description = "Passed through purely to force Cloud SQL/Redis to wait on the peering connection (see root network.tf) — not otherwise used."
  type        = any
}

variable "tickets_web_domain" {
  description = "Custom domain for tickets-web. Empty string means no domain mapping (staging)."
  type        = string
  default     = ""
}

variable "ga_measurement_id" {
  description = "Google Analytics 4 measurement ID for tickets-web. Only wired into the production container — see the variable of the same name in the root module."
  type        = string
  default     = ""
}

variable "jwt_access_token_ttl_seconds" {
  description = "How long a sign-in JWT stays valid, for auth-service's container — see the variable of the same name in the root module."
  type        = number
  default     = 10800
}

variable "auth_service_domain" {
  description = "Custom domain for festival-auth-service. Empty string means no domain mapping (staging)."
  type        = string
  default     = ""
}

variable "tickets_api_domain" {
  description = "Custom domain for tickets-api."
  type        = string
  default     = ""
}
