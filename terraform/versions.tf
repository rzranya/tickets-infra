terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # No backend block on purpose for now — state stays local until we
  # decide where remote state should live (a GCS bucket, created by this
  # same config, is the natural next step but that's a chicken-and-egg
  # problem for a first apply). Revisit before more than one person
  # touches this.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
