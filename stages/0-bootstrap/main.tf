locals {
  labels = {
    team        = "plataforma"
    owner       = replace(replace(lower(var.owner), "@", "-"), ".", "-")
    cost_center = lower(var.cost_center)
    expires     = "never"
    managed_by  = "terraform"
  }

  seed_services = [
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "orgpolicy.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]

  # Una cuenta de servicio por etapa, con sus roles a nivel organización.
  # En el Sprint 2 se acotan a carpeta (ver ADR-0004).
  stages = {
    org = {
      description = "Etapa 1: carpetas, org policies, logging y SCC"
      org_roles = [
        "roles/resourcemanager.folderAdmin",
        "roles/orgpolicy.policyAdmin",
        "roles/logging.configWriter",
        "roles/securitycenter.settingsAdmin",
      ]
    }
    security = {
      description = "Etapa 2: KMS, Secret Manager y VPC-SC"
      org_roles = [
        "roles/accesscontextmanager.policyAdmin",
        "roles/cloudkms.admin",
        "roles/resourcemanager.projectCreator",
      ]
    }
    networks = {
      description = "Etapa 3: hub, spokes, DNS, VPN y PSC"
      org_roles = [
        "roles/compute.xpnAdmin",
        "roles/compute.networkAdmin",
        "roles/dns.admin",
        "roles/resourcemanager.projectCreator",
      ]
    }
    ai-platform = {
      description = "Etapa 4: datos, Vertex AI compartido, GKE GPU y guardrails"
      org_roles = [
        "roles/resourcemanager.projectCreator",
        "roles/serviceusage.serviceUsageAdmin",
      ]
    }
    sandboxes = {
      description = "Etapa 5: un proyecto por equipo"
      org_roles = [
        "roles/resourcemanager.projectCreator",
        "roles/resourcemanager.projectDeleter",
      ]
    }
  }

  stage_org_roles = {
    for pair in flatten([
      for stage, cfg in local.stages : [
        for role in cfg.org_roles : { stage = stage, role = role }
      ]
    ]) : "${pair.stage}/${pair.role}" => pair
  }

  # Etapas que crean proyectos necesitan asociarles la facturación.
  billing_user_stages = ["security", "networks", "ai-platform", "sandboxes"]
}

resource "random_id" "suffix" {
  byte_length = 2
}

# Carpeta y proyecto semilla ------------------------------------------------

resource "google_folder" "bootstrap" {
  display_name        = "bootstrap"
  parent              = "organizations/${var.org_id}"
  deletion_protection = true
}

resource "google_project" "seed" {
  name                = "${var.prefix}-seed"
  project_id          = "${var.prefix}-seed-${random_id.suffix.hex}"
  folder_id           = google_folder.bootstrap.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"
  labels              = local.labels
}

resource "google_project_service" "seed" {
  for_each = toset(local.seed_services)

  project            = google_project.seed.project_id
  service            = each.value
  disable_on_destroy = false
}

# Llave para el estado (CMEK) ----------------------------------------------

resource "google_kms_key_ring" "tfstate" {
  project  = google_project.seed.project_id
  name     = "tfstate-${var.region}"
  location = var.region

  depends_on = [google_project_service.seed]
}

resource "google_kms_crypto_key" "tfstate" {
  name            = "tfstate"
  key_ring        = google_kms_key_ring.tfstate.id
  rotation_period = "7776000s" # 90 días
  purpose         = "ENCRYPT_DECRYPT"
  labels          = local.labels
}

data "google_storage_project_service_account" "gcs" {
  project = google_project.seed.project_id

  depends_on = [google_project_service.seed]
}

resource "google_kms_crypto_key_iam_member" "gcs_cmek" {
  crypto_key_id = google_kms_crypto_key.tfstate.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

# Bucket del estado remoto (ADR-0003) --------------------------------------

resource "google_storage_bucket" "tfstate" {
  project                     = google_project.seed.project_id
  name                        = "${var.prefix}-tfstate-${random_id.suffix.hex}"
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.labels

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.tfstate.id
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.tfstate_noncurrent_versions
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# Cuentas de servicio por etapa --------------------------------------------

resource "google_service_account" "stage" {
  for_each = local.stages

  project      = google_project.seed.project_id
  account_id   = "sa-${each.key}"
  display_name = "Terraform ${each.key}"
  description  = each.value.description
}

resource "google_organization_iam_member" "stage" {
  for_each = local.stage_org_roles

  org_id = var.org_id
  role   = each.value.role
  member = "serviceAccount:${google_service_account.stage[each.value.stage].email}"
}

resource "google_billing_account_iam_member" "stage_billing_user" {
  for_each = toset(local.billing_user_stages)

  billing_account_id = var.billing_account
  role               = "roles/billing.user"
  member             = "serviceAccount:${google_service_account.stage[each.value].email}"
}

resource "google_billing_account_iam_member" "sandboxes_costs" {
  billing_account_id = var.billing_account
  role               = "roles/billing.costsManager"
  member             = "serviceAccount:${google_service_account.stage["sandboxes"].email}"
}

resource "google_storage_bucket_iam_member" "stage_tfstate" {
  for_each = local.stages

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.stage[each.key].email}"
}

# Workload Identity Federation para GitHub Actions (ADR-0004) --------------

resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.seed.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "Identidades del pipeline de ${var.github_repo}"

  depends_on = [google_project_service.seed]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = google_project.seed.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Solo el repo del proyecto puede obtener credenciales.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "stage_wif" {
  for_each = local.stages

  service_account_id = google_service_account.stage[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
