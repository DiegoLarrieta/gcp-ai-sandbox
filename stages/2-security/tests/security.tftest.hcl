# Pruebas de la etapa 2 con mock_provider (ADR-0005).

mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-300000000001@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
  mock_data "google_bigquery_default_service_account" {
    defaults = {
      email = "bq-300000000001@bigquery-encryption.iam.gserviceaccount.com"
    }
  }
}

mock_provider "google-beta" {
  mock_resource "google_project_service_identity" {
    defaults = {
      email = "service-300000000001@gcp-sa-aiplatform.iam.gserviceaccount.com"
    }
  }
}

variables {
  tfstate_bucket = "acme-tfstate-abcd"
  admin_members  = ["user:admin@empresa.com"]
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      seed_project_id = "acme-seed-abcd"
      access_policy   = "accessPolicies/555555555555"
      stage_service_accounts = {
        org       = "sa-org@acme-seed-abcd.iam.gserviceaccount.com"
        sandboxes = "sa-sandboxes@acme-seed-abcd.iam.gserviceaccount.com"
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.org
  values = {
    outputs = {
      projects = {
        security    = { project_id = "acme-security-abcd", number = "300000000003" }
        ai-platform = { project_id = "acme-ai-platform-abcd", number = "300000000004" }
        ai-data     = { project_id = "acme-ai-data-abcd", number = "300000000005" }
      }
    }
  }
}

run "llaves_cmek_con_rotacion" {
  command = plan

  assert {
    condition     = toset(keys(google_kms_crypto_key.key)) == toset(["storage", "bigquery", "aiplatform", "compute"])
    error_message = "Debe haber una llave por servicio."
  }

  assert {
    condition     = alltrue([for k in google_kms_crypto_key.key : k.rotation_period == "7776000s"])
    error_message = "Todas las llaves deben rotar cada 90 días."
  }

  assert {
    condition     = google_kms_key_ring.ai_sandbox.project == "acme-security-abcd"
    error_message = "Las llaves deben vivir en el proyecto security, fuera del perímetro."
  }
}

run "agentes_pueden_cifrar" {
  command = plan

  assert {
    condition     = length(google_kms_crypto_key_iam_member.agent) == 8
    error_message = "Cada proyecto protegido necesita permiso sobre sus cuatro llaves."
  }

  assert {
    condition     = google_kms_crypto_key_iam_member.agent["ai-data/compute"].member == "serviceAccount:service-300000000005@compute-system.iam.gserviceaccount.com"
    error_message = "El agente de Compute debe derivarse del número del proyecto."
  }
}

run "perimetro_protege_datos_e_ia" {
  command = plan

  assert {
    condition     = toset(google_access_context_manager_service_perimeter.ai_sandbox.status[0].resources) == toset(["projects/300000000004", "projects/300000000005"])
    error_message = "El perímetro debe envolver ai-platform y ai-data."
  }

  assert {
    condition     = alltrue([for s in ["storage.googleapis.com", "bigquery.googleapis.com", "aiplatform.googleapis.com"] : contains(google_access_context_manager_service_perimeter.ai_sandbox.status[0].restricted_services, s)])
    error_message = "Storage, BigQuery y Vertex AI deben estar restringidos."
  }

  assert {
    condition     = !contains(google_access_context_manager_service_perimeter.ai_sandbox.status[0].restricted_services, "cloudkms.googleapis.com")
    error_message = "KMS no se restringe: las llaves están fuera del perímetro."
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.ai_sandbox.parent == "accessPolicies/555555555555"
    error_message = "El perímetro debe vivir en la política con alcance de la carpeta raíz."
  }
}

run "sin_salida_del_perimetro" {
  command = plan

  assert {
    condition     = length(google_access_context_manager_service_perimeter.ai_sandbox.status[0].egress_policies) == 0
    error_message = "No debe existir ninguna regla de salida: copiar datos fuera del perímetro debe fallar."
  }

  assert {
    condition     = contains(google_access_context_manager_service_perimeter.ai_sandbox.status[0].ingress_policies[0].ingress_from[0].identities, "user:admin@empresa.com")
    error_message = "Los admins deben poder entrar al perímetro."
  }
}

run "modo_simulacion" {
  command = plan

  variables {
    dry_run = true
  }

  assert {
    condition     = length(google_access_context_manager_service_perimeter.ai_sandbox.status) == 0 && length(google_access_context_manager_service_perimeter.ai_sandbox.spec) == 1
    error_message = "En dry_run el perímetro solo debe registrar, sin bloquear."
  }
}

run "rechaza_admin_mal_formado" {
  command = plan

  variables {
    admin_members = ["admin@empresa.com"]
  }

  expect_failures = [var.admin_members]
}
