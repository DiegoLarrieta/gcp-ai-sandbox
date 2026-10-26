variable "org_id" {
  description = "ID numérico de la organización de GCP."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{8,20}$", var.org_id))
    error_message = "org_id debe ser numérico, por ejemplo 123456789012."
  }
}

variable "billing_account" {
  description = "ID de la cuenta de facturación (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener el formato XXXXXX-XXXXXX-XXXXXX en mayúsculas."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para nombres de recursos (2 a 10 caracteres)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe empezar con letra y tener de 2 a 10 caracteres en minúsculas o números."
  }
}

variable "region" {
  description = "Región principal (ver ADR-0002)."
  type        = string
  default     = "us-central1"

  validation {
    condition     = contains(["us-central1", "us-east4"], var.region)
    error_message = "Solo se permiten us-central1 y us-east4."
  }
}

variable "github_repo" {
  description = "Repositorio que puede autenticarse por WIF, en formato owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo debe tener el formato owner/repo."
  }
}

variable "owner" {
  description = "Grupo dueño de la plataforma, para la etiqueta owner."
  type        = string
  default     = "gcp-ai-plataforma"
}

variable "cost_center" {
  description = "Centro de costos para la etiqueta cost_center."
  type        = string
  default     = "plataforma"
}

variable "tfstate_noncurrent_versions" {
  description = "Versiones no actuales del estado que se conservan por archivo."
  type        = number
  default     = 10

  validation {
    condition     = var.tfstate_noncurrent_versions >= 3
    error_message = "Conserva al menos 3 versiones anteriores del estado."
  }
}
