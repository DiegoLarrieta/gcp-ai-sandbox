# Etapa 3: Shared VPC hub, subredes, Cloud NAT, firewall con lista de
# dominios, DNS hacia Private Service Connect, PSA y HA VPN.

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "stages/0-bootstrap"
  }
}

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "stages/1-org"
  }
}

locals {
  projects   = data.terraform_remote_state.org.outputs.projects
  folders    = data.terraform_remote_state.org.outputs.folders
  host       = local.projects["net-hub"].project_id
  spokes     = ["ai-platform", "ai-data"]
  internal   = ["10.0.0.0/8", "100.64.0.0/10", var.onprem_range]
  psc_bundle = "vpc-sc"

  # docs/plan-ip.md
  subnets = {
    hub-usc1 = {
      region = var.region
      cidr   = "10.0.0.0/24"
      ranges = {}
    }
    hub-use4 = {
      region = var.secondary_region
      cidr   = "10.0.1.0/24"
      ranges = {}
    }
    ai-platform-gke = {
      region = var.region
      cidr   = "10.0.16.0/20"
      ranges = { pods = "100.64.0.0/14", services = "100.68.0.0/20" }
    }
    ai-data-dataflow = {
      region = var.region
      cidr   = "10.0.32.0/20"
      ranges = {}
    }
  }
}

# Shared VPC ---------------------------------------------------------------

resource "google_compute_shared_vpc_host_project" "hub" {
  project = local.host
}

resource "google_compute_shared_vpc_service_project" "spoke" {
  for_each = toset(local.spokes)

  host_project    = google_compute_shared_vpc_host_project.hub.project
  service_project = local.projects[each.value].project_id
}

resource "google_compute_network" "hub" {
  # checkov:skip=CKV2_GCP_18:El firewall es una network firewall policy (google_compute_network_firewall_policy.hub); checkov solo detecta reglas clásicas.
  project                                   = local.host
  name                                      = "vpc-hub"
  auto_create_subnetworks                   = false
  routing_mode                              = "GLOBAL"
  network_firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
}

resource "google_compute_subnetwork" "subnet" {
  for_each = local.subnets

  project                  = local.host
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

# Salida a Internet: Cloud NAT + firewall con lista de dominios -----------

resource "google_compute_router" "nat" {
  project = local.host
  region  = var.region
  name    = "cr-nat-${var.region}"
  network = google_compute_network.hub.id
}

resource "google_compute_router_nat" "nat" {
  project                            = local.host
  region                             = var.region
  name                               = "nat-${var.region}"
  router                             = google_compute_router.nat.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}

resource "google_compute_network_firewall_policy" "hub" {
  project     = local.host
  name        = "fw-hub"
  description = "Salida solo hacia dominios permitidos y APIs de Google por PSC."
}

resource "google_compute_network_firewall_policy_association" "hub" {
  project           = local.host
  name              = "fw-hub-vpc-hub"
  firewall_policy   = google_compute_network_firewall_policy.hub.name
  attachment_target = google_compute_network.hub.id
}

resource "google_compute_network_firewall_policy_rule" "allow_iap" {
  project         = local.host
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
  project         = local.host
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
  project         = local.host
  firewall_policy = google_compute_network_firewall_policy.hub.name
  priority        = 2000
  direction       = "EGRESS"
  action          = "allow"
  description     = "Interno, on-premises y el endpoint PSC de las APIs de Google."

  match {
    dest_ip_ranges = local.internal
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allow_fqdns" {
  project         = local.host
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
  project         = local.host
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

# Firewall jerárquico: ai-sandbox nunca alcanza producción ----------------

resource "google_compute_firewall_policy" "ai_sandbox" {
  parent      = local.folders.root
  short_name  = "fw-ai-sandbox"
  description = "Los sandboxes no tienen rutas hacia proyectos productivos."
}

resource "google_compute_firewall_policy_rule" "deny_production" {
  firewall_policy = google_compute_firewall_policy.ai_sandbox.name
  priority        = 1000
  direction       = "EGRESS"
  action          = "deny"
  description     = "Bloquea cualquier tráfico hacia rangos de producción."
  enable_logging  = true

  match {
    dest_ip_ranges = var.production_ranges
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_firewall_policy_association" "ai_sandbox" {
  name              = "fw-ai-sandbox"
  firewall_policy   = google_compute_firewall_policy.ai_sandbox.name
  attachment_target = local.folders.ai_sandbox
}

# Private Service Connect para las APIs de Google -------------------------

resource "google_compute_global_address" "psc_apis" {
  project      = local.host
  name         = "psc-googleapis"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = var.psc_address
  network      = google_compute_network.hub.id
}

resource "google_compute_global_forwarding_rule" "psc_apis" {
  project               = local.host
  name                  = "pscvpcsc"
  target                = local.psc_bundle
  network               = google_compute_network.hub.id
  ip_address            = google_compute_global_address.psc_apis.id
  load_balancing_scheme = ""
}

# DNS: *.googleapis.com y *.pkg.dev resuelven al endpoint PSC del bundle
# vpc-sc, así el tráfico a las APIs nunca sale a Internet.
resource "google_dns_managed_zone" "private" {
  for_each = toset(["googleapis.com.", "pkg.dev."])

  project     = local.host
  name        = replace(trimsuffix(each.value, "."), ".", "-")
  dns_name    = each.value
  visibility  = "private"
  description = "Resuelve ${each.value} al endpoint PSC."

  private_visibility_config {
    networks {
      network_url = google_compute_network.hub.id
    }
  }
}

resource "google_dns_record_set" "psc_a" {
  for_each = google_dns_managed_zone.private

  project      = local.host
  managed_zone = each.value.name
  name         = each.key == "googleapis.com." ? "restricted.googleapis.com." : each.key
  type         = "A"
  ttl          = 300
  rrdatas      = [var.psc_address]
}

resource "google_dns_record_set" "psc_wildcard" {
  for_each = google_dns_managed_zone.private

  project      = local.host
  managed_zone = each.value.name
  name         = "*.${each.key}"
  type         = each.key == "googleapis.com." ? "CNAME" : "A"
  ttl          = 300
  rrdatas      = each.key == "googleapis.com." ? ["restricted.googleapis.com."] : [var.psc_address]
}

# Private Service Access (Vertex AI Vector Search, Cloud SQL) -------------

resource "google_compute_global_address" "psa" {
  project       = local.host
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
  # checkov:skip=CKV2_GCP_18:Red de laboratorio que simula on-premises; solo recibe tráfico por el HA VPN y existe mientras dura la prueba.
  count = var.enable_hybrid ? 1 : 0

  project                 = local.host
  name                    = "vpc-onprem-sim"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "onprem" {
  count = var.enable_hybrid ? 1 : 0

  project                  = local.host
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

module "hybrid" {
  source = "../../modules/hybrid-connectivity"
  count  = var.enable_hybrid ? 1 : 0

  project_id     = local.host
  region         = var.region
  hub_network    = google_compute_network.hub.self_link
  onprem_network = google_compute_network.onprem[0].self_link
}
