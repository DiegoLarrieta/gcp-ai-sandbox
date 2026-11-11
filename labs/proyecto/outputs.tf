output "project_number" {
  description = "Número del proyecto."
  value       = data.google_project.this.number
}

output "storage_key" {
  description = "Llave CMEK de Cloud Storage."
  value       = google_kms_crypto_key.key["storage"].id
}

output "psc_address" {
  description = "IP del endpoint PSC."
  value       = google_compute_global_address.psc_apis.address
}

output "vpn_tunnels" {
  description = "Túneles HA VPN."
  value       = var.enable_hybrid ? module.hybrid[0].tunnels : []
}
