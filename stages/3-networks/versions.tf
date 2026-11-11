terraform {
  required_version = ">= 1.9.0"

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

  backend "gcs" {
    prefix = "stages/3-networks"
  }
}

provider "google" {
  region                = var.region
  user_project_override = true
  billing_project       = data.terraform_remote_state.bootstrap.outputs.seed_project_id
}
