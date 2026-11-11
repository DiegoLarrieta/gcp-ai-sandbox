# Laboratorio del Sprint 2 en un solo proyecto, sin organización (ADR-0009).
# Despliega de verdad la red, la salida controlada, PSC, DNS, PSA, HA VPN y
# CMEK. Lo que exige organización (carpetas, org policies, Shared VPC,
# firewall jerárquico y VPC-SC) vive en stages/1 a 3 y se valida con mocks.

locals {
  internal = ["10.0.0.0/8", "100.64.0.0/10", var.onprem_range]

  services = [
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "networksecurity.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage.googleapis.com",
  ]

  subnets = {
    hub-usc1         = { region = var.region, cidr = "10.0.0.0/24", ranges = {} }
    hub-use4         = { region = "us-east4", cidr = "10.0.1.0/24", ranges = {} }
    ai-platform-gke  = { region = var.region, cidr = "10.0.16.0/20", ranges = { pods = "100.64.0.0/14", services = "100.68.0.0/20" } }
    ai-data-dataflow = { region = var.region, cidr = "10.0.32.0/20", ranges = {} }
  }

  labels = {
    team        = "plataforma"
    owner       = "gcp-ai-plataforma"
    cost_center = "plataforma"
    expires     = "2026-12-31"
    managed_by  = "terraform"
  }
}

resource "google_project_service" "this" {
  for_each           = toset(local.services)
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {}

# Auditoría de acceso a datos en el proyecto.
resource "google_project_iam_audit_config" "all" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# CMEK ---------------------------------------------------------------------

resource "google_kms_key_ring" "lab" {
  name       = "ai-sandbox-${var.region}"
  location   = var.region
  depends_on = [google_project_service.this]
}

resource "google_kms_crypto_key" "key" {
  for_each = toset(["storage", "compute"])

  name            = each.value
  key_ring        = google_kms_key_ring.lab.id
  rotation_period = "7776000s"
  labels          = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

data "google_storage_project_service_account" "gcs" {
  depends_on = [google_project_service.this]
}

resource "google_kms_crypto_key_iam_member" "gcs" {
  crypto_key_id = google_kms_crypto_key.key["storage"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_secret_manager_secret" "huggingface" {
  secret_id = "huggingface-token"
  labels    = local.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.this]
}

# Red ----------------------------------------------------------------------

resource "google_compute_network" "hub" {
  # checkov:skip=CKV2_GCP_18:El firewall es una network firewall policy; checkov solo detecta reglas clásicas.
  name                                      = "vpc-hub"
  auto_create_subnetworks                   = false
  routing_mode                              = "GLOBAL"
  network_firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
  depends_on                                = [google_project_service.this]
}

resource "google_compute_subnetwork" "subnet" {
  for_each = local.subnets

  name                     = each.key
  region                   = each.value.region
  network                  = google_compute_network.hub.id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = each.value.ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "nat" {
  name    = "cr-nat-${var.region}"
  region  = var.region
  network = google_compute_network.hub.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-${var.region}"
  region                             = var.region
  router                             = google_compute_router.nat.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}

resource "google_compute_network_firewall_policy" "hub" {
  name        = "fw-hub"
  description = "Salida solo hacia dominios permitidos y APIs de Google por PSC."
  depends_on  = [google_project_service.this]
}

resource "google_compute_network_firewall_policy_association" "hub" {
  name              = "fw-hub-vpc-hub"
  firewall_policy   = google_compute_network_firewall_policy.hub.name
  attachment_target = google_compute_network.hub.id
}

resource "google_compute_network_firewall_policy_rule" "allow_iap" {
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 1000
  direction       = "INGRESS"
  action          = "allow"
  description     = "SSH por IAP, sin IP públicas."
  enable_logging  = true

  match {
    src_ip_ranges = ["35.235.240.0/20"]
    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["22"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_internal_ingress" {
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 1100
  direction       = "INGRESS"
  action          = "allow"
  description     = "Tráfico interno, pods de GKE y on-premises."

  match {
    src_ip_ranges = local.internal
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_internal_egress" {
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 2000
  direction       = "EGRESS"
  action          = "allow"
  description     = "Interno, on-premises y el endpoint PSC."

  match {
    dest_ip_ranges = local.internal
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_fqdns" {
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 3000
  direction       = "EGRESS"
  action          = "allow"
  description     = "Repositorios de paquetes y de modelos permitidos."
  enable_logging  = true

  match {
    dest_fqdns = var.allowed_egress_fqdns
    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "deny_internet" {
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 65000
  direction       = "EGRESS"
  action          = "deny"
  description     = "Todo lo demás hacia Internet se bloquea y se registra."
  enable_logging  = true

  match {
    dest_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

# Private Service Connect para las APIs de Google -------------------------

resource "google_compute_global_address" "psc_apis" {
  name         = "psc-googleapis"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = var.psc_address
  network      = google_compute_network.hub.id
}

# Sin organización no hay VPC-SC, así que se usa el bundle all-apis.
resource "google_compute_global_forwarding_rule" "psc_apis" {
  name                  = "pscallapis"
  target                = "all-apis"
  network               = google_compute_network.hub.id
  ip_address            = google_compute_global_address.psc_apis.id
  load_balancing_scheme = ""
}

resource "google_dns_managed_zone" "googleapis" {
  name        = "googleapis-com"
  dns_name    = "googleapis.com."
  visibility  = "private"
  description = "Resuelve las APIs de Google al endpoint PSC."

  private_visibility_config {
    networks {
      network_url = google_compute_network.hub.id
    }
  }
  depends_on = [google_project_service.this]
}

resource "google_dns_record_set" "private_googleapis" {
  managed_zone = google_dns_managed_zone.googleapis.name
  name         = "private.googleapis.com."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.psc_address]
}

resource "google_dns_record_set" "wildcard_googleapis" {
  managed_zone = google_dns_managed_zone.googleapis.name
  name         = "*.googleapis.com."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["private.googleapis.com."]
}

# Private Service Access --------------------------------------------------

resource "google_compute_global_address" "psa" {
  name          = "psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.0.64.0"
  prefix_length = 20
  network       = google_compute_network.hub.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.hub.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

# HA VPN contra el on-premises simulado (ADR-0008) ------------------------

resource "google_compute_network" "onprem" {
  # checkov:skip=CKV2_GCP_18:Red de laboratorio que simula on-premises; existe solo durante la prueba.
  count                   = var.enable_hybrid ? 1 : 0
  name                    = "vpc-onprem-sim"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "onprem" {
  count                    = var.enable_hybrid ? 1 : 0
  name                     = "onprem-sim"
  region                   = var.region
  network                  = google_compute_network.onprem[0].id
  ip_cidr_range            = var.onprem_range
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "onprem_from_hub" {
  count     = var.enable_hybrid ? 1 : 0
  name      = "onprem-allow-hub-and-iap"
  network   = google_compute_network.onprem[0].id
  direction = "INGRESS"

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["10.0.0.0/16", "35.235.240.0/20"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

module "hybrid" {
  source = "../../modules/hybrid-connectivity"
  count  = var.enable_hybrid ? 1 : 0

  project_id     = var.project_id
  region         = var.region
  hub_network    = google_compute_network.hub.self_link
  onprem_network = google_compute_network.onprem[0].self_link
}
