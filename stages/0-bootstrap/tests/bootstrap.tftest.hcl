# Pruebas unitarias de la etapa 0 con mock_provider (ADR-0005).
# No requieren credenciales ni cuenta de GCP.

mock_provider "google" {
  source = "./tests/mocks"
}

mock_provider "google-beta" {
  source = "./tests/mocks"
}

variables {
  org_id          = "123456789012"
  billing_account = "000000-AAAAAA-BBBBBB"
  prefix          = "acme"
  region          = "us-central1"
  github_repo     = "DiegoLarrieta/gcp-ai-sandbox"
  owner           = "gcp-ai-plataforma@empresa.com"
}

run "bucket_de_estado_seguro" {
  command = plan

  assert {
    condition     = google_storage_bucket.tfstate.versioning[0].enabled
    error_message = "El bucket de estado debe tener versionado."
  }

  assert {
    condition     = length(google_storage_bucket.tfstate.encryption) == 1
    error_message = "El bucket de estado debe estar cifrado con CMEK."
  }

  assert {
    condition     = google_storage_bucket.tfstate.public_access_prevention == "enforced"
    error_message = "El bucket de estado debe bloquear el acceso público."
  }

  assert {
    condition     = google_storage_bucket.tfstate.uniform_bucket_level_access
    error_message = "El bucket de estado debe usar acceso uniforme."
  }

  assert {
    condition     = google_storage_bucket.tfstate.force_destroy == false
    error_message = "El bucket de estado no debe poder borrarse con contenido."
  }
}

run "llave_kms_con_rotacion" {
  command = plan

  assert {
    condition     = google_kms_crypto_key.tfstate.rotation_period == "7776000s"
    error_message = "La llave del estado debe rotar cada 90 días."
  }

  assert {
    condition     = google_kms_crypto_key_iam_member.gcs_cmek.role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    error_message = "El agente de Cloud Storage necesita permiso sobre la llave."
  }
}

run "wif_solo_acepta_el_repo_del_proyecto" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub == 'repo:DiegoLarrieta/gcp-ai-sandbox:ref:refs/heads/main' || assertion.sub == 'repo:DiegoLarrieta/gcp-ai-sandbox:pull_request'"
    error_message = "WIF debe aceptar solo tokens del repo del proyecto, desde main o desde un PR."
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.sub == 'repo:DiegoLarrieta/gcp-ai-sandbox:ref:refs/heads/main'")
    error_message = "WIF debe limitar las credenciales a la rama main y a los PR."
  }

  assert {
    condition     = !strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "*")
    error_message = "La condición de WIF no debe usar comodines."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.oidc[0].issuer_uri == "https://token.actions.githubusercontent.com"
    error_message = "El proveedor OIDC debe ser GitHub Actions."
  }

  assert {
    condition = alltrue([
      for m in google_service_account_iam_member.stage_wif :
      m.role == "roles/iam.workloadIdentityUser"
    ])
    error_message = "Las cuentas de etapa solo se suplantan vía workloadIdentityUser."
  }
}

run "una_cuenta_por_etapa_sin_privilegios_amplios" {
  command = plan

  assert {
    condition     = toset(keys(google_service_account.stage)) == toset(["org", "security", "networks", "ai-platform", "sandboxes"])
    error_message = "Debe existir exactamente una cuenta de servicio por etapa."
  }

  assert {
    condition = alltrue([
      for b in google_organization_iam_member.stage :
      !contains(["roles/owner", "roles/editor"], b.role)
    ])
    error_message = "Ninguna cuenta de etapa puede tener Owner o Editor."
  }

  assert {
    condition = alltrue([
      for sa in google_service_account.stage :
      length(sa.account_id) >= 6 && length(sa.account_id) <= 30
    ])
    error_message = "Los IDs de cuenta de servicio deben medir entre 6 y 30 caracteres."
  }
}

run "etiquetas_obligatorias" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["team", "owner", "cost_center", "expires", "managed_by"] :
      contains(keys(google_project.seed.labels), k)
    ])
    error_message = "El proyecto semilla debe llevar las cinco etiquetas obligatorias."
  }

  assert {
    condition     = google_project.seed.labels.owner == "gcp-ai-plataforma-empresa-com"
    error_message = "La etiqueta owner debe normalizar @ y puntos."
  }

  assert {
    condition     = google_project.seed.auto_create_network == false
    error_message = "El proyecto semilla no debe crear la red default."
  }
}

# La llave KMS tiene prevent_destroy, así que un run con command = apply
# no podría limpiarse al terminar. En su lugar se fijan los valores
# calculados durante el plan para poder revisar los outputs completos.
run "outputs_con_valores_fijos" {
  command = plan

  override_resource {
    target          = random_id.suffix
    override_during = plan
    values = {
      hex = "abcd"
    }
  }

  override_resource {
    target          = google_iam_workload_identity_pool_provider.github
    override_during = plan
    values = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/github/providers/github-actions"
    }
  }

  override_resource {
    target          = google_service_account.stage
    override_during = plan
    values = {
      name  = "projects/acme-seed-abcd/serviceAccounts/sa-mock@acme-seed-abcd.iam.gserviceaccount.com"
      email = "sa-mock@acme-seed-abcd.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = output.seed_project_id == "acme-seed-abcd"
    error_message = "El proyecto semilla debe seguir la convención de nombres."
  }

  assert {
    condition     = output.tfstate_bucket == "acme-tfstate-abcd"
    error_message = "El bucket de estado debe seguir la convención de nombres."
  }

  assert {
    condition     = endswith(output.wif_provider, "/providers/github-actions")
    error_message = "El output wif_provider debe apuntar al proveedor de GitHub."
  }

  assert {
    condition     = length(output.stage_service_accounts) == 5
    error_message = "Debe haber un correo por cada etapa."
  }
}

# Casos que deben fallar ---------------------------------------------------

run "rechaza_region_no_permitida" {
  command = plan

  variables {
    region = "europe-west1"
  }

  expect_failures = [var.region]
}

run "rechaza_org_id_mal_formado" {
  command = plan

  variables {
    org_id = "mi-organizacion"
  }

  expect_failures = [var.org_id]
}

run "rechaza_cuenta_de_facturacion_mal_formada" {
  command = plan

  variables {
    billing_account = "000000-aaaaaa-bbbbbb"
  }

  expect_failures = [var.billing_account]
}

run "rechaza_repo_sin_owner" {
  command = plan

  variables {
    github_repo = "gcp-ai-sandbox"
  }

  expect_failures = [var.github_repo]
}
