# Reglas que todo sandbox debe cumplir para ser aprobado.
# Se evalúan en cada PR contra stages/5-sandboxes/teams/*.yaml:
#   conftest test stages/5-sandboxes/teams -p policies/sandbox
package main

import rego.v1

required_fields := {"team", "owner_group", "cost_center", "expires", "monthly_budget_usd", "network_index"}

known_services := {"workbench", "vertex-training", "vertex-endpoints", "vector-search", "gke-gpu", "bigquery", "agents"}

allowed_model_families := {"gemini", "gemma", "llama"}

# Cuota máxima sin aprobación adicional. H100 y TPU siempre requieren solicitud.
gpu_limits := {"nvidia-l4": 4, "nvidia-a100": 1}

gpu_needs_approval := {"nvidia-h100", "tpu-v5e", "tpu-v5p"}

max_budget_usd := 5000

max_days := 365

approved if {
	is_string(input.approved_by)
	count(input.approved_by) > 0
}

deny contains msg if {
	some field in required_fields
	not field in object.keys(input)
	msg := sprintf("Falta el campo obligatorio '%s'.", [field])
}

# Fecha de expiración ------------------------------------------------------

expires_ns := time.parse_rfc3339_ns(sprintf("%sT00:00:00Z", [substring(sprintf("%v", [input.expires]), 0, 10)]))

deny contains msg if {
	input.expires
	not expires_ns
	msg := "expires debe tener el formato AAAA-MM-DD."
}

deny contains msg if {
	expires_ns <= time.now_ns()
	msg := sprintf("La fecha de expiración %v ya pasó.", [input.expires])
}

deny contains msg if {
	expires_ns > time.now_ns() + (((max_days * 24) * 3600) * 1000000000)
	msg := sprintf("Un sandbox no puede durar más de %d días; pide una renovación al vencer.", [max_days])
}

# Presupuesto ---------------------------------------------------------------

deny contains msg if {
	not input.monthly_budget_usd > 0
	"monthly_budget_usd" in object.keys(input)
	msg := "monthly_budget_usd debe ser mayor a cero."
}

deny contains msg if {
	input.monthly_budget_usd > max_budget_usd
	not approved
	msg := sprintf("Un presupuesto mayor a %d USD requiere approved_by.", [max_budget_usd])
}

# Dueño ---------------------------------------------------------------------

deny contains msg if {
	not regex.match(`^[a-z0-9._-]+@[a-z0-9.-]+\.[a-z]+$`, input.owner_group)
	msg := "owner_group debe ser el correo de un grupo."
}

# Red -----------------------------------------------------------------------

deny contains msg if {
	"network_index" in object.keys(input)
	not valid_network_index
	msg := "network_index debe ser un entero entre 0 y 63 (ver docs/plan-ip.md)."
}

valid_network_index if {
	is_number(input.network_index)
	input.network_index == floor(input.network_index)
	input.network_index >= 0
	input.network_index <= 63
}

# GPU y TPU -----------------------------------------------------------------

deny contains msg if {
	some gpu, n in input.gpu_quota
	limit := gpu_limits[gpu]
	n > limit
	not approved
	msg := sprintf("La cuota de %s (%d) supera el máximo de %d sin aprobación.", [gpu, n, limit])
}

deny contains msg if {
	some gpu, n in input.gpu_quota
	gpu in gpu_needs_approval
	n > 0
	not approved
	msg := sprintf("%s solo se asigna con solicitud aprobada (approved_by).", [gpu])
}

deny contains msg if {
	some gpu, _ in input.gpu_quota
	not gpu_limits[gpu]
	not gpu in gpu_needs_approval
	msg := sprintf("Acelerador desconocido: %s.", [gpu])
}

# Servicios, datos y modelos ------------------------------------------------

deny contains msg if {
	some svc in input.allowed_services
	not svc in known_services
	msg := sprintf("Servicio no permitido: %s.", [svc])
}

deny contains msg if {
	some path in input.data_access
	not startswith(path, "curated/")
	msg := sprintf("Solo se puede leer la zona curated; '%s' no está permitido.", [path])
}

deny contains msg if {
	some model in input.models
	not model in allowed_model_families
	msg := sprintf("La familia de modelos '%s' no está en la lista permitida.", [model])
}
