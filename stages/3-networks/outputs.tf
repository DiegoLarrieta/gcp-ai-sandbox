output "network" {
  description = "VPC hub compartida."
  value       = google_compute_network.hub.self_link
}

output "subnets" {
  description = "Subredes por nombre."
  value       = { for k, s in google_compute_subnetwork.subnet : k => s.self_link }
}

output "psc_address" {
  description = "IP del endpoint PSC de las APIs de Google."
  value       = google_compute_global_address.psc_apis.address
}

output "vpn_tunnels" {
  description = "Túneles HA VPN (vacío si enable_hybrid = false)."
  value       = var.enable_hybrid ? module.hybrid[0].tunnels : []
}
