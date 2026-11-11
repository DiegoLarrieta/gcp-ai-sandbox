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

  # El bucket se pasa al iniciar: terraform init -backend-config="bucket=..."
  backend "gcs" {
    prefix = "stages/1-org"
  }
}

provider "google" {
  region                = var.region
  user_project_override = true
  billing_project       = data.terraform_remote_state.bootstrap.outputs.seed_project_id
}
