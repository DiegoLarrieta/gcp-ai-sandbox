# Etapa 1: carpetas, proyectos base, org policies y logging centralizado.
# Todo queda dentro de la carpeta raíz creada por 0-bootstrap (ADR-0006).

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "stages/0-bootstrap"
  }
}

locals {
  root_folder = data.terraform_remote_state.bootstrap.outputs.root_folder

  labels = {
    team        = "plataforma"
    owner       = replace(replace(lower(var.owner), "@", "-"), ".", "-")
    cost_center = "plataforma"
    expires     = "never"
    managed_by  = "terraform"
  }

  base_services = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
  ]

  # Proyectos base de la plataforma. Los de ai-sandbox quedan dentro del
  # perímetro VPC-SC (etapa 2); los de common, fuera.
  projects = {
    logging = {
      folder   = "common"
      services = []
    }
    security = {
      folder   = "common"
      services = ["cloudkms.googleapis.com", "secretmanager.googleapis.com"]
    }
    net-hub = {
      folder   = "common"
      services = ["dns.googleapis.com", "servicenetworking.googleapis.com", "networksecurity.googleapis.com"]
    }
    ai-platform = {
      folder   = "ai-sandbox"
      services = ["aiplatform.googleapis.com", "artifactregistry.googleapis.com", "container.googleapis.com", "notebooks.googleapis.com", "storage.googleapis.com"]
    }
    ai-data = {
      folder   = "ai-sandbox"
      services = ["bigquery.googleapis.com", "dlp.googleapis.com", "storage.googleapis.com"]
    }
  }

  folder_names = {
    common     = google_folder.common.name
    ai-sandbox = google_folder.ai_sandbox.name
  }
}

resource "random_id" "suffix" {
  byte_length = 2
}

# Carpetas (ADR-0001) ------------------------------------------------------

resource "google_folder" "common" {
  display_name        = "common"
  parent              = local.root_folder
  deletion_protection = false
}

resource "google_folder" "ai_sandbox" {
  display_name        = "ai-sandbox"
  parent              = local.root_folder
  deletion_protection = false
}

# Proyectos base -----------------------------------------------------------

module "project" {
  source   = "../../modules/project"
  for_each = local.projects

  name            = each.key
  project_id      = "${var.prefix}-${each.key}-${random_id.suffix.hex}"
  folder          = local.folder_names[each.value.folder]
  billing_account = var.billing_account
  labels          = local.labels
  services        = concat(local.base_services, each.value.services)
}

# Org policies sobre la carpeta raíz ---------------------------------------

resource "google_org_policy_policy" "resource_locations" {
  name   = "${local.root_folder}/policies/gcp.resourceLocations"
  parent = local.root_folder

  spec {
    rules {
      values {
        allowed_values = [for r in var.allowed_regions : "in:${r}-locations"]
      }
    }
  }
}

resource "google_org_policy_policy" "vm_external_ip" {
  name   = "${local.root_folder}/policies/compute.vmExternalIpAccess"
  parent = local.root_folder

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "boolean" {
  for_each = toset([
    "iam.disableServiceAccountKeyCreation",
    "compute.skipDefaultNetworkCreation",
    "compute.requireOsLogin",
    "storage.uniformBucketLevelAccess",
    "storage.publicAccessPrevention",
  ])

  name   = "${local.root_folder}/policies/${each.value}"
  parent = local.root_folder

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# CMEK obligatorio en ai-sandbox (Storage, BigQuery y Vertex AI), solo con
# llaves del proyecto security.
resource "google_org_policy_policy" "restrict_non_cmek" {
  name   = "${google_folder.ai_sandbox.name}/policies/gcp.restrictNonCmekServices"
  parent = google_folder.ai_sandbox.name

  spec {
    rules {
      values {
        denied_values = ["storage.googleapis.com", "bigquery.googleapis.com", "aiplatform.googleapis.com"]
      }
    }
  }
}

resource "google_org_policy_policy" "cmek_key_projects" {
  name   = "${google_folder.ai_sandbox.name}/policies/gcp.restrictCmekCryptoKeyProjects"
  parent = google_folder.ai_sandbox.name

  spec {
    rules {
      values {
        allowed_values = ["under:projects/${module.project["security"].project_id}"]
      }
    }
  }
}

# Logging centralizado -----------------------------------------------------

# Auditoría de lectura y escritura de datos en toda la carpeta raíz. Junto
# con los logs de políticas (siempre activos) deja registro de cualquier
# intento de sacar datos del perímetro.
resource "google_folder_iam_audit_config" "root" {
  folder  = local.root_folder
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_logging_project_bucket_config" "audit" {
  project        = module.project["logging"].project_id
  location       = var.region
  bucket_id      = "audit-logs"
  retention_days = var.log_retention_days
  description    = "Auditoría de toda la carpeta gcp-ai-sandbox, incluidas violaciones de VPC-SC."
}

resource "google_logging_folder_sink" "audit" {
  name             = "audit-logs"
  folder           = local.root_folder
  include_children = true
  destination      = "logging.googleapis.com/${google_logging_project_bucket_config.audit.id}"
  filter           = "logName:\"cloudaudit.googleapis.com\""
}

resource "google_project_iam_member" "sink_writer" {
  project = module.project["logging"].project_id
  role    = "roles/logging.bucketWriter"
  member  = google_logging_folder_sink.audit.writer_identity
}
