# HA VPN con BGP entre la VPC hub y una red "on-premises".
# En el reto, on-premises se simula con otra VPC (ADR-0008).
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "project_id" {
  description = "Proyecto donde viven ambas puntas del VPN."
  type        = string
}

variable "region" {
  description = "Región del VPN."
  type        = string
}

variable "hub_network" {
  description = "self_link de la VPC hub."
  type        = string
}

variable "onprem_network" {
  description = "self_link de la VPC que simula on-premises."
  type        = string
}

variable "hub_asn" {
  description = "ASN privado del Cloud Router de la hub."
  type        = number
  default     = 64514
}

variable "onprem_asn" {
  description = "ASN privado del lado on-premises."
  type        = number
  default     = 64515
}

variable "hub_advertised_ranges" {
  description = "Rangos que la hub anuncia a on-premises (docs/plan-ip.md)."
  type        = list(string)
  default     = ["10.0.0.0/16", "10.10.0.0/16"]
}

locals {
  # Un /30 de 169.254.0.0/24 por túnel.
  tunnels = {
    "0" = { hub_ip = "169.254.0.1", onprem_ip = "169.254.0.2" }
    "1" = { hub_ip = "169.254.0.5", onprem_ip = "169.254.0.6" }
  }
}

resource "random_password" "psk" {
  for_each = local.tunnels
  length   = 32
  special  = false
}

resource "google_compute_ha_vpn_gateway" "hub" {
  project = var.project_id
  region  = var.region
  name    = "vpn-hub"
  network = var.hub_network
}

resource "google_compute_ha_vpn_gateway" "onprem" {
  project = var.project_id
  region  = var.region
  name    = "vpn-onprem"
  network = var.onprem_network
}

resource "google_compute_router" "hub" {
  project = var.project_id
  region  = var.region
  name    = "cr-vpn-hub"
  network = var.hub_network

  bgp {
    asn               = var.hub_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = []

    dynamic "advertised_ip_ranges" {
      for_each = var.hub_advertised_ranges
      content {
        range = advertised_ip_ranges.value
      }
    }
  }
}

resource "google_compute_router" "onprem" {
  project = var.project_id
  region  = var.region
  name    = "cr-vpn-onprem"
  network = var.onprem_network

  bgp {
    asn = var.onprem_asn
  }
}

resource "google_compute_vpn_tunnel" "hub" {
  for_each = local.tunnels

  project               = var.project_id
  region                = var.region
  name                  = "tunnel-hub-${each.key}"
  vpn_gateway           = google_compute_ha_vpn_gateway.hub.id
  vpn_gateway_interface = tonumber(each.key)
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem.id
  shared_secret         = random_password.psk[each.key].result
  router                = google_compute_router.hub.id
}

resource "google_compute_vpn_tunnel" "onprem" {
  for_each = local.tunnels

  project               = var.project_id
  region                = var.region
  name                  = "tunnel-onprem-${each.key}"
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem.id
  vpn_gateway_interface = tonumber(each.key)
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub.id
  shared_secret         = random_password.psk[each.key].result
  router                = google_compute_router.onprem.id
}

resource "google_compute_router_interface" "hub" {
  for_each = local.tunnels

  project    = var.project_id
  region     = var.region
  name       = "if-hub-${each.key}"
  router     = google_compute_router.hub.name
  ip_range   = "${each.value.hub_ip}/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub[each.key].name
}

resource "google_compute_router_interface" "onprem" {
  for_each = local.tunnels

  project    = var.project_id
  region     = var.region
  name       = "if-onprem-${each.key}"
  router     = google_compute_router.onprem.name
  ip_range   = "${each.value.onprem_ip}/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem[each.key].name
}

resource "google_compute_router_peer" "hub" {
  for_each = local.tunnels

  project         = var.project_id
  region          = var.region
  name            = "peer-hub-${each.key}"
  router          = google_compute_router.hub.name
  peer_ip_address = each.value.onprem_ip
  peer_asn        = var.onprem_asn
  interface       = google_compute_router_interface.hub[each.key].name
}

resource "google_compute_router_peer" "onprem" {
  for_each = local.tunnels

  project         = var.project_id
  region          = var.region
  name            = "peer-onprem-${each.key}"
  router          = google_compute_router.onprem.name
  peer_ip_address = each.value.hub_ip
  peer_asn        = var.hub_asn
  interface       = google_compute_router_interface.onprem[each.key].name
}

output "tunnels" {
  description = "Túneles de la hub."
  value       = [for t in google_compute_vpn_tunnel.hub : t.name]
}

output "hub_router" {
  description = "Cloud Router de la hub, para revisar el estado de BGP."
  value       = google_compute_router.hub.name
}
