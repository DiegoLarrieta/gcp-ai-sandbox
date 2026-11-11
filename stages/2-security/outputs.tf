output "kms_keys" {
  description = "Llave CMEK por servicio."
  value       = { for k, v in google_kms_crypto_key.key : k => v.id }
}

output "perimeter" {
  description = "Nombre del perímetro VPC-SC."
  value       = google_access_context_manager_service_perimeter.ai_sandbox.name
}

output "huggingface_secret" {
  description = "Secreto donde va el token de Hugging Face."
  value       = google_secret_manager_secret.huggingface.id
}
