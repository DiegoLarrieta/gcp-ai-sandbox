# Pruebas de la fábrica de sandboxes con mock_provider (ADR-0005).

mock_provider "google" {
  mock_resource "google_project" {
    defaults = {
      number = "333333333333"
    }
  }
}

variables {
  prefix          = "acme"
  billing_account = "000000-AAAAAA-BBBBBB"
  folder_id       = "folders/444444444444"
  teams_dir       = "tests/fixtures/validos"
}

run "un_proyecto_por_yaml" {
  command = plan

  assert {
    condition     = toset(keys(google_project.sandbox)) == toset(["analitica", "vision"])
    error_message = "Debe crearse un proyecto por cada archivo YAML."
  }

  assert {
    condition     = google_project.sandbox["analitica"].project_id == "acme-aisbx-analitica"
    error_message = "El proyecto debe llamarse <prefix>-aisbx-<equipo>."
  }

  assert {
    condition     = google_project.sandbox["analitica"].folder_id == "444444444444"
    error_message = "Los sandboxes deben quedar en la carpeta ai-sandbox."
  }

  assert {
    condition     = google_project.sandbox["analitica"].auto_create_network == false
    error_message = "Los sandboxes no deben crear la red default."
  }
}

run "etiquetas_desde_el_yaml" {
  command = plan

  assert {
    condition = google_project.sandbox["analitica"].labels == tomap({
      team        = "analitica"
      owner       = "gcp-ai-analitica-empresa-com"
      cost_center = "cc-1042"
      expires     = "2027-03-31"
      managed_by  = "terraform"
    })
    error_message = "Las cinco etiquetas obligatorias deben salir del YAML."
  }
}

run "presupuesto_con_alertas" {
  command = plan

  assert {
    condition     = google_billing_budget.sandbox["analitica"].amount[0].specified_amount[0].units == "3000"
    error_message = "El presupuesto debe ser el monthly_budget_usd del YAML."
  }

  assert {
    condition     = [for t in google_billing_budget.sandbox["analitica"].threshold_rules : t.threshold_percent] == [0.5, 0.8, 1.0]
    error_message = "Las alertas deben estar al 50, 80 y 100 %."
  }
}

run "apis_segun_servicios_permitidos" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.sandbox), "vision/container.googleapis.com")
    error_message = "gke-gpu debe habilitar la API de GKE."
  }

  assert {
    condition     = !contains(keys(google_project_service.sandbox), "analitica/container.googleapis.com")
    error_message = "Un equipo sin gke-gpu no debe tener la API de GKE."
  }
}

run "rangos_de_ip_por_indice" {
  command = plan

  assert {
    condition     = output.sandbox_networks["analitica"].subnet == "10.10.0.0/22" && output.sandbox_networks["vision"].subnet == "10.10.4.0/22"
    error_message = "Cada sandbox debe recibir su /22 según network_index (docs/plan-ip.md)."
  }

  assert {
    condition     = output.sandbox_networks["vision"].pods == "100.80.64.0/18"
    error_message = "El rango de pods debe derivarse del mismo índice."
  }
}

run "apply_completo_con_mocks" {
  command = apply

  assert {
    condition     = output.sandbox_projects["vision"] == "acme-aisbx-vision"
    error_message = "El output debe listar el proyecto de cada equipo."
  }
}

# Casos que deben fallar ---------------------------------------------------

run "rechaza_sandbox_sin_expiracion" {
  command = plan

  variables {
    teams_dir = "tests/fixtures/sin-expiracion"
  }

  expect_failures = [google_project.sandbox]
}

run "rechaza_indice_de_red_repetido" {
  command = plan

  variables {
    teams_dir = "tests/fixtures/indice-repetido"
  }

  expect_failures = [google_project.sandbox]
}
