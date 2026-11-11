# Etapa 2: llaves CMEK, Secret Manager y perímetro VPC Service Controls.

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "stages/0-bootstrap"
  }
}

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "stages/1-org"
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
  projects  = data.terraform_remote_state.org.outputs.projects

  security_project = local.projects["security"].project_id

  # Proyectos dentro del perímetro.
  protected = ["ai-platform", "ai-data"]

  keys = ["storage", "bigquery", "aiplatform", "compute"]

  # Agentes de servicio que cifran con cada llave, por proyecto protegido.
  agents = merge(
    { for p in local.protected : "${p}/storage" => {
      key    = "storage"
      member = "serviceAccount:${data.google_storage_project_service_account.gcs[p].email_address}"
    } },
    { for p in local.protected : "${p}/bigquery" => {
      key    = "bigquery"
      member = "serviceAccount:${data.google_bigquery_default_service_account.bq[p].email}"
    } },
    { for p in local.protected : "${p}/aiplatform" => {
      key    = "aiplatform"
      member = "serviceAccount:${google_project_service_identity.aiplatform[p].email}"
    } },
    { for p in local.protected : "${p}/compute" => {
      key    = "compute"
      member = "serviceAccount:service-${local.projects[p].number}@compute-system.iam.gserviceaccount.com"
    } },
  )

  # Quién puede entrar al perímetro desde fuera: el pipeline y los admins.
  ingress_identities = concat(
    [for k, sa in local.bootstrap.stage_service_accounts : "serviceAccount:${sa}"],
    var.admin_members,
  )
}

# Cloud KMS ----------------------------------------------------------------

resource "google_kms_key_ring" "ai_sandbox" {
  project  = local.security_project
  name     = "ai-sandbox-${var.region}"
  location = var.region
}

resource "google_kms_crypto_key" "key" {
  for_each = toset(local.keys)

  name            = each.value
  key_ring        = google_kms_key_ring.ai_sandbox.id
  rotation_period = "7776000s" # 90 días
  purpose         = "ENCRYPT_DECRYPT"
  labels = {
    team       = "plataforma"
    managed_by = "terraform"
  }

  # Borrar una llave deja ilegibles todos los datos cifrados con ella.
  lifecycle {
    prevent_destroy = true
  }
}

data "google_storage_project_service_account" "gcs" {
  for_each = toset(local.protected)
  project  = local.projects[each.value].project_id
}

data "google_bigquery_default_service_account" "bq" {
  for_each = toset(local.protected)
  project  = local.projects[each.value].project_id
}

resource "google_project_service_identity" "aiplatform" {
  provider = google-beta
  for_each = toset(local.protected)

  project = local.projects[each.value].project_id
  service = "aiplatform.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "agent" {
  for_each = local.agents

  crypto_key_id = google_kms_crypto_key.key[each.value.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = each.value.member
}

# Secret Manager -----------------------------------------------------------

# Contenedor para el token de Hugging Face que usarán los equipos para bajar
# modelos abiertos. El valor lo carga una persona, nunca Terraform.
resource "google_secret_manager_secret" "huggingface" {
  project   = local.security_project
  secret_id = "huggingface-token"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = {
    team       = "plataforma"
    managed_by = "terraform"
  }
}

# VPC Service Controls (ADR-0007) -----------------------------------------

resource "google_access_context_manager_service_perimeter" "ai_sandbox" {
  parent                    = local.bootstrap.access_policy
  name                      = "${local.bootstrap.access_policy}/servicePerimeters/ai_sandbox"
  title                     = "ai_sandbox"
  perimeter_type            = "PERIMETER_TYPE_REGULAR"
  use_explicit_dry_run_spec = var.dry_run

  dynamic "status" {
    for_each = var.dry_run ? [] : [1]
    content {
      resources           = [for p in local.protected : "projects/${local.projects[p].number}"]
      restricted_services = var.restricted_services

      vpc_accessible_services {
        enable_restriction = true
        allowed_services   = ["RESTRICTED-SERVICES"]
      }

      ingress_policies {
        ingress_from {
          identities = local.ingress_identities
          sources {
            access_level = "*"
          }
        }
        ingress_to {
          resources = ["*"]
          operations {
            service_name = "*"
          }
        }
      }
    }
  }

  dynamic "spec" {
    for_each = var.dry_run ? [1] : []
    content {
      resources           = [for p in local.protected : "projects/${local.projects[p].number}"]
      restricted_services = var.restricted_services

      vpc_accessible_services {
        enable_restriction = true
        allowed_services   = ["RESTRICTED-SERVICES"]
      }

      ingress_policies {
        ingress_from {
          identities = local.ingress_identities
          sources {
            access_level = "*"
          }
        }
        ingress_to {
          resources = ["*"]
          operations {
            service_name = "*"
          }
        }
      }
    }
  }
}
