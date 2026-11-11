# Proyecto con facturación, etiquetas obligatorias y APIs habilitadas.
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "name" {
  description = "Nombre corto del proyecto, por ejemplo ai-data."
  type        = string
}

variable "project_id" {
  description = "ID global del proyecto (6 a 30 caracteres)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe tener de 6 a 30 caracteres en minúsculas, números o guiones."
  }
}

variable "folder" {
  description = "Carpeta padre en formato folders/NNN."
  type        = string
}

variable "billing_account" {
  description = "Cuenta de facturación."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias (team, owner, cost_center, expires, managed_by)."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["team", "owner", "cost_center", "expires", "managed_by"] : contains(keys(var.labels), k)])
    error_message = "Faltan etiquetas obligatorias."
  }
}

variable "services" {
  description = "APIs que se habilitan en el proyecto."
  type        = list(string)
  default     = []
}

resource "google_project" "this" {
  # checkov:skip=CKV2_GCP_5:La auditoría de acceso a datos se configura una vez en la carpeta raíz (stages/1-org, google_folder_iam_audit_config.root) y la heredan todos los proyectos.
  name                = var.name
  project_id          = var.project_id
  folder_id           = trimprefix(var.folder, "folders/")
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"
  labels              = var.labels
}

resource "google_project_service" "this" {
  for_each = toset(var.services)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

output "project_id" {
  description = "ID del proyecto."
  value       = google_project.this.project_id
}

output "number" {
  description = "Número del proyecto."
  value       = google_project.this.number
}
