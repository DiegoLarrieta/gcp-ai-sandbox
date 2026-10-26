terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Se activa en el Sprint 5 con el bucket creado por 0-bootstrap.
  # backend "gcs" {
  #   bucket = "<tfstate_bucket>"
  #   prefix = "stages/5-sandboxes"
  # }
}

provider "google" {
  region = var.region
}
