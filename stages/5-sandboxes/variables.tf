variable "prefix" {
  description = "Prefijo de la empresa, el mismo de 0-bootstrap."
  type        = string
}

variable "billing_account" {
  description = "Cuenta de facturación a la que se asocian los sandboxes."
  type        = string
}

variable "folder_id" {
  description = "Carpeta ai-sandbox, en formato folders/NNN (output de la etapa 1)."
  type        = string

  validation {
    condition     = can(regex("^folders/[0-9]+$", var.folder_id))
    error_message = "folder_id debe tener el formato folders/NNN."
  }
}

variable "region" {
  description = "Región principal."
  type        = string
  default     = "us-central1"
}

variable "teams_dir" {
  description = "Carpeta con un YAML por sandbox."
  type        = string
  default     = "teams"
}
