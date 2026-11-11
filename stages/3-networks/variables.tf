variable "tfstate_bucket" {
  description = "Bucket del estado remoto (output tfstate_bucket de 0-bootstrap)."
  type        = string
}

variable "region" {
  description = "Región principal."
  type        = string
  default     = "us-central1"
}

variable "secondary_region" {
  description = "Región alterna para GPU (ADR-0002)."
  type        = string
  default     = "us-east4"
}

variable "enable_hybrid" {
  description = "Crea el HA VPN contra el on-premises simulado. Cuesta unos 0.10 USD por hora; se apaga al terminar las pruebas."
  type        = bool
  default     = false
}

variable "psc_address" {
  description = "IP interna del endpoint de Private Service Connect para las APIs de Google (docs/plan-ip.md)."
  type        = string
  default     = "10.0.200.10"
}

variable "allowed_egress_fqdns" {
  description = "Únicos dominios de Internet que los sandboxes pueden alcanzar: repositorios de paquetes y de modelos."
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

variable "production_ranges" {
  description = "Rangos de producción hacia los que ai-sandbox nunca puede enviar tráfico."
  type        = list(string)
  default     = ["10.128.0.0/9"]
}

variable "onprem_range" {
  description = "Rango del on-premises simulado (supuesto en docs/plan-ip.md)."
  type        = string
  default     = "172.16.0.0/24"
}
