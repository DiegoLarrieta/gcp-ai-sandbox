# Pruebas de las políticas: conftest verify -p policies
package main

import rego.v1

valid := {
	"team": "analitica",
	"owner_group": "gcp-ai-analitica@empresa.com",
	"cost_center": "cc-1042",
	"expires": "2027-03-31",
	"monthly_budget_usd": 3000,
	"network_index": 0,
	"gpu_quota": {"nvidia-l4": 4, "nvidia-a100": 1},
	"allowed_services": ["workbench", "vertex-training"],
	"data_access": ["curated/ventas"],
	"models": ["gemini", "gemma"],
}

now := time.parse_rfc3339_ns("2026-10-26T12:00:00Z")

test_sandbox_valido_pasa if {
	count(deny) == 0 with input as valid with time.now_ns as now
}

test_rechaza_sin_expiracion if {
	inp := object.remove(valid, ["expires"])
	"Falta el campo obligatorio 'expires'." in deny with input as inp with time.now_ns as now
}

test_rechaza_sin_presupuesto if {
	inp := object.remove(valid, ["monthly_budget_usd"])
	"Falta el campo obligatorio 'monthly_budget_usd'." in deny with input as inp with time.now_ns as now
}

test_rechaza_expiracion_pasada if {
	inp := object.union(valid, {"expires": "2026-01-01"})
	count(deny) == 1 with input as inp with time.now_ns as now
}

test_rechaza_expiracion_mayor_a_un_anio if {
	inp := object.union(valid, {"expires": "2028-06-01"})
	count(deny) == 1 with input as inp with time.now_ns as now
}

test_rechaza_cuota_l4_excedida if {
	inp := object.union(valid, {"gpu_quota": {"nvidia-l4": 8}})
	"La cuota de nvidia-l4 (8) supera el máximo de 4 sin aprobación." in deny with input as inp with time.now_ns as now
}

test_rechaza_h100_sin_aprobacion if {
	inp := object.union(valid, {"gpu_quota": {"nvidia-h100": 1}})
	"nvidia-h100 solo se asigna con solicitud aprobada (approved_by)." in deny with input as inp with time.now_ns as now
}

test_permite_h100_con_aprobacion if {
	inp := object.union(valid, {"gpu_quota": {"nvidia-h100": 1}, "approved_by": "comite-ia@empresa.com"})
	count(deny) == 0 with input as inp with time.now_ns as now
}

test_rechaza_acceso_a_zona_raw if {
	inp := object.union(valid, {"data_access": ["raw/clientes"]})
	"Solo se puede leer la zona curated; 'raw/clientes' no está permitido." in deny with input as inp with time.now_ns as now
}

test_rechaza_modelo_no_permitido if {
	inp := object.union(valid, {"models": ["mistral"]})
	"La familia de modelos 'mistral' no está en la lista permitida." in deny with input as inp with time.now_ns as now
}

test_rechaza_servicio_desconocido if {
	inp := object.union(valid, {"allowed_services": ["compute-engine"]})
	"Servicio no permitido: compute-engine." in deny with input as inp with time.now_ns as now
}

test_rechaza_presupuesto_alto_sin_aprobacion if {
	inp := object.union(valid, {"monthly_budget_usd": 9000})
	count(deny) == 1 with input as inp with time.now_ns as now
}

test_rechaza_indice_de_red_fuera_de_rango if {
	inp := object.union(valid, {"network_index": 64})
	count(deny) == 1 with input as inp with time.now_ns as now
}
