# Pruebas de la etapa 1 con mock_provider (ADR-0005).

mock_provider "google" {}
mock_provider "random" {}

variables {
  tfstate_bucket  = "acme-tfstate-abcd"
  billing_account = "000000-AAAAAA-BBBBBB"
  prefix          = "acme"
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      root_folder     = "folders/100000000001"
      seed_project_id = "acme-seed-abcd"
    }
  }
}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "abcd"
  }
}

override_resource {
  target          = google_folder.ai_sandbox
  override_during = plan
  values = {
    name = "folders/100000000003"
  }
}

run "carpetas_dentro_de_la_raiz" {
  command = plan

  assert {
    condition     = google_folder.common.parent == "folders/100000000001" && google_folder.ai_sandbox.parent == "folders/100000000001"
    error_message = "common y ai-sandbox deben colgar de la carpeta raíz, no de la organización."
  }
}

run "proyectos_base" {
  command = plan

  assert {
    condition     = toset(keys(module.project)) == toset(["logging", "security", "net-hub", "ai-platform", "ai-data"])
    error_message = "Deben existir los cinco proyectos base."
  }

  assert {
    condition     = module.project["ai-data"].project_id == "acme-ai-data-abcd"
    error_message = "Los proyectos deben llamarse <prefix>-<nombre>-<sufijo>."
  }
}

run "org_policies_en_la_raiz" {
  command = plan

  assert {
    condition     = google_org_policy_policy.resource_locations.spec[0].rules[0].values[0].allowed_values == tolist(["in:us-central1-locations", "in:us-east4-locations"])
    error_message = "Solo se permiten us-central1 y us-east4."
  }

  assert {
    condition     = google_org_policy_policy.vm_external_ip.spec[0].rules[0].deny_all == "TRUE"
    error_message = "Ninguna VM puede tener IP pública."
  }

  assert {
    condition     = contains(keys(google_org_policy_policy.boolean), "iam.disableServiceAccountKeyCreation")
    error_message = "Debe prohibirse crear llaves de cuentas de servicio."
  }

  assert {
    condition = alltrue(concat(
      [for p in google_org_policy_policy.boolean : p.parent == "folders/100000000001"],
      [google_org_policy_policy.resource_locations.parent == "folders/100000000001"]
    ))
    error_message = "Ninguna org policy debe aplicarse a la organización completa."
  }
}

run "cmek_obligatorio_en_ai_sandbox" {
  command = plan

  assert {
    condition     = google_org_policy_policy.restrict_non_cmek.parent == "folders/100000000003"
    error_message = "CMEK obligatorio debe aplicarse a la carpeta ai-sandbox."
  }

  assert {
    condition     = contains(google_org_policy_policy.restrict_non_cmek.spec[0].rules[0].values[0].denied_values, "storage.googleapis.com")
    error_message = "Cloud Storage debe exigir CMEK."
  }
}

run "logs_de_auditoria_centralizados" {
  command = plan

  assert {
    condition     = google_logging_folder_sink.audit.include_children && google_logging_folder_sink.audit.folder == "folders/100000000001"
    error_message = "El sink debe capturar toda la carpeta raíz."
  }

  assert {
    condition     = strcontains(google_logging_folder_sink.audit.filter, "cloudaudit.googleapis.com")
    error_message = "El sink debe incluir los audit logs, donde quedan las violaciones de VPC-SC."
  }

  assert {
    condition     = length(google_folder_iam_audit_config.root.audit_log_config) == 3
    error_message = "Toda la carpeta debe auditar lecturas y escrituras de datos."
  }
}

run "rechaza_region_no_permitida" {
  command = plan

  variables {
    allowed_regions = ["us-central1", "europe-west1"]
  }

  expect_failures = [var.allowed_regions]
}
