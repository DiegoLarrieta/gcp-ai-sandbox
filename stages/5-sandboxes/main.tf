# Fábrica de sandboxes: un proyecto por cada archivo teams/<equipo>.yaml.
# Las reglas de negocio (cuotas máximas, modelos, zona raw) las valida
# Conftest en el PR; aquí solo se protege lo que rompería el despliegue.
# En los sprints 3 a 5 se agregan subred, cuotas de GPU, IAM por rol y el
# apagado automático por presupuesto.

locals {
  teams = {
    for f in fileset(var.teams_dir, "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${var.teams_dir}/${f}"))
  }

  service_apis = {
    workbench        = ["notebooks.googleapis.com", "aiplatform.googleapis.com"]
    vertex-training  = ["aiplatform.googleapis.com", "artifactregistry.googleapis.com"]
    vertex-endpoints = ["aiplatform.googleapis.com"]
    vector-search    = ["aiplatform.googleapis.com"]
    gke-gpu          = ["container.googleapis.com"]
    bigquery         = ["bigquery.googleapis.com"]
    agents           = ["aiplatform.googleapis.com", "run.googleapis.com"]
  }

  base_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
  ]

  team_apis = {
    for pair in flatten([
      for team, cfg in local.teams : [
        for api in distinct(concat(
          local.base_apis,
          flatten([for s in try(cfg.allowed_services, []) : lookup(local.service_apis, s, [])])
        )) : { team = team, api = api }
      ]
    ]) : "${pair.team}/${pair.api}" => pair
  }

  # yamldecode convierte una fecha sin comillas en timestamp
  # (2027-03-31T00:00:00Z); nos quedamos solo con AAAA-MM-DD.
  expires = {
    for team, cfg in local.teams :
    team => try(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}", tostring(cfg.expires)), null)
  }

  network_indexes = [for cfg in local.teams : try(cfg.network_index, -1)]

  networks = {
    for team, cfg in local.teams : team => {
      subnet   = cidrsubnet("10.10.0.0/16", 6, cfg.network_index)
      pods     = cidrsubnet("100.80.0.0/12", 6, cfg.network_index)
      services = cidrsubnet("100.96.0.0/16", 8, cfg.network_index)
    } if try(cfg.network_index >= 0 && cfg.network_index <= 63, false)
  }
}

resource "google_project" "sandbox" {
  # checkov:skip=CKV2_GCP_5:La auditoría de Data Access se configura una vez a nivel organización en la etapa 1-org y la heredan todos los sandboxes.
  for_each = local.teams

  name                = "aisbx-${each.key}"
  project_id          = "${var.prefix}-aisbx-${each.key}"
  folder_id           = trimprefix(var.folder_id, "folders/")
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"

  labels = {
    team        = each.key
    owner       = replace(replace(lower(each.value.owner_group), "@", "-"), ".", "-")
    cost_center = lower(each.value.cost_center)
    expires     = coalesce(local.expires[each.key], "missing")
    managed_by  = "terraform"
  }

  lifecycle {
    precondition {
      condition     = each.key == each.value.team
      error_message = "El nombre del archivo debe coincidir con el campo team."
    }
    precondition {
      condition     = local.expires[each.key] != null
      error_message = "Cada sandbox necesita expires con formato AAAA-MM-DD."
    }
    precondition {
      condition     = try(each.value.monthly_budget_usd > 0, false)
      error_message = "Cada sandbox necesita monthly_budget_usd mayor a cero."
    }
    precondition {
      condition     = contains(keys(local.networks), each.key)
      error_message = "network_index debe ser un entero entre 0 y 63."
    }
    precondition {
      condition     = length(distinct(local.network_indexes)) == length(local.network_indexes)
      error_message = "network_index está repetido entre sandboxes."
    }
  }
}

resource "google_project_service" "sandbox" {
  for_each = local.team_apis

  project            = google_project.sandbox[each.value.team].project_id
  service            = each.value.api
  disable_on_destroy = false
}

resource "google_billing_budget" "sandbox" {
  for_each = local.teams

  billing_account = var.billing_account
  display_name    = "aisbx-${each.key}"

  budget_filter {
    projects = ["projects/${google_project.sandbox[each.key].number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(each.value.monthly_budget_usd)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.8, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }
}
