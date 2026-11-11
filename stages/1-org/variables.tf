variable "tfstate_bucket" {
  description = "Bucket del estado remoto (output tfstate_bucket de 0-bootstrap)."
  type        = string
}

variable "billing_account" {
  description = "Cuenta de facturación de los proyectos base."
  type        = string
}

variable "prefix" {
  description = "Prefijo de la empresa, el mismo de 0-bootstrap."
  type        = string
}

variable "region" {
  description = "Región principal."
  type        = string
  default     = "us-central1"
}

variable "allowed_regions" {
  description = "Regiones permitidas por la org policy gcp.resourceLocations (ADR-0002)."
  type        = list(string)
  default     = ["us-central1", "us-east4"]

  validation {
    condition     = length(setsubtract(var.allowed_regions, ["us-central1", "us-east4"])) == 0
    error_message = "Solo se permiten us-central1 y us-east4."
  }
}

variable "log_retention_days" {
  description = "Días que se conservan los logs de auditoría centralizados."
  type        = number
  default     = 30
}

variable "owner" {
  description = "Grupo dueño de la plataforma, para la etiqueta owner."
  type        = string
  default     = "gcp-ai-plataforma"
}
