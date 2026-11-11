output "folders" {
  description = "Carpetas de la jerarquía."
  value = {
    root       = local.root_folder
    common     = google_folder.common.name
    ai_sandbox = google_folder.ai_sandbox.name
  }
}

output "projects" {
  description = "ID y número de cada proyecto base."
  value = {
    for k, p in module.project : k => {
      project_id = p.project_id
      number     = p.number
    }
  }
}

output "audit_log_bucket" {
  description = "Bucket de logs donde quedan las violaciones de VPC-SC."
  value       = google_logging_project_bucket_config.audit.id
}
