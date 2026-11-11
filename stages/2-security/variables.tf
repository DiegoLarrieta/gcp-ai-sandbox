variable "tfstate_bucket" {
  description = "Bucket del estado remoto (output tfstate_bucket de 0-bootstrap)."
  type        = string
}

variable "region" {
  description = "Región principal."
  type        = string
  default     = "us-central1"
}

variable "admin_members" {
  description = "Personas que administran la plataforma desde fuera del perímetro, por ejemplo user:diego@empresa.com."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.admin_members : can(regex("^(user|group):", m))])
    error_message = "Cada admin debe empezar con user: o group:."
  }
}

variable "restricted_services" {
  description = "APIs que el perímetro protege. Cloud KMS queda fuera porque las llaves viven en el proyecto security."
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "container.googleapis.com",
    "dlp.googleapis.com",
    "notebooks.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

variable "dry_run" {
  description = "true deja el perímetro en modo simulación: registra las violaciones sin bloquear."
  type        = bool
  default     = false
}
