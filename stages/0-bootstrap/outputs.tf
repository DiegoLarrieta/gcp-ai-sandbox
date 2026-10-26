output "seed_project_id" {
  description = "Proyecto semilla con el estado y las identidades del pipeline."
  value       = google_project.seed.project_id
}

output "bootstrap_folder" {
  description = "Carpeta bootstrap (folders/NNN)."
  value       = google_folder.bootstrap.name
}

output "tfstate_bucket" {
  description = "Bucket del estado remoto para el bloque backend gcs de cada etapa."
  value       = google_storage_bucket.tfstate.name
}

output "tfstate_kms_key" {
  description = "Llave CMEK del bucket de estado."
  value       = google_kms_crypto_key.tfstate.id
}

output "wif_provider" {
  description = "Valor para la variable WIF_PROVIDER del repo en GitHub."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "stage_service_accounts" {
  description = "Correo de la cuenta de servicio de cada etapa."
  value       = { for k, sa in google_service_account.stage : k => sa.email }
}
