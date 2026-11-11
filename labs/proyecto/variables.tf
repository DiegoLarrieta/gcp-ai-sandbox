variable "project_id" {
  description = "Proyecto donde se despliega el laboratorio."
  type        = string
}

variable "region" {
  description = "Región principal (ADR-0002)."
  type        = string
  default     = "us-central1"

  validation {
    condition     = contains(["us-central1", "us-east4"], var.region)
    error_message = "Solo se permiten us-central1 y us-east4."
  }
}

variable "enable_hybrid" {
  description = "Crea el HA VPN contra el on-premises simulado (unos 0.20 USD por hora)."
  type        = bool
  default     = false
}

variable "psc_address" {
  description = "IP del endpoint PSC de las APIs de Google (docs/plan-ip.md)."
  type        = string
  default     = "10.0.200.10"
}

variable "onprem_range" {
  description = "Rango del on-premises simulado."
  type        = string
  default     = "172.16.0.0/24"
}

variable "allowed_egress_fqdns" {
  description = "Únicos dominios de Internet alcanzables: repositorios de paquetes y de modelos."
  type        = list(string)
  default = [
    "pypi.org",
    "files.pythonhosted.org",
    "huggingface.co",
    "cdn-lfs.huggingface.co",
    "cdn-lfs-us-1.huggingface.co",
    "github.com",
    "objects.githubusercontent.com",
    "download.pytorch.org",
    "registry.npmjs.org",
    "conda.anaconda.org",
    "repo.anaconda.com",
  ]
}
