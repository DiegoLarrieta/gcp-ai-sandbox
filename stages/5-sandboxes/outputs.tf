output "sandbox_projects" {
  description = "Proyecto creado para cada equipo."
  value       = { for k, p in google_project.sandbox : k => p.project_id }
}

output "sandbox_networks" {
  description = "Rangos de IP asignados a cada sandbox (ver docs/plan-ip.md)."
  value       = local.networks
}
