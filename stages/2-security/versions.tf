terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    prefix = "stages/2-security"
  }
}

provider "google" {
  region                = var.region
  user_project_override = true
  billing_project       = data.terraform_remote_state.bootstrap.outputs.seed_project_id
}

provider "google-beta" {
  region                = var.region
  user_project_override = true
  billing_project       = data.terraform_remote_state.bootstrap.outputs.seed_project_id
}
