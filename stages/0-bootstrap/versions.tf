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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # La etapa 0 arranca con estado local. Tras el primer apply, descomenta
  # este bloque con el bucket del output `tfstate_bucket` y corre
  # `terraform init -migrate-state` (ver ADR-0003).
  #
  # backend "gcs" {
  #   bucket = "<tfstate_bucket>"
  #   prefix = "stages/0-bootstrap"
  # }
}

provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}
